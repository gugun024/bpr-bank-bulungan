import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/protocol.dart';
import '../shared/sounds.dart';
import '../shared/theme.dart';

/// Window penonton: fullscreen di monitor kedua / proyektor.
/// Dikendalikan penuh dari window operator via WindowMethodChannel.
///
/// Layout mengikuti mockup SATU GAYA IMERSIF yang disetujui Gugun
/// (mockup-layout-satu-gaya.html) + sistem hadiah otomatis dari
/// mockup-hadiah-final.html: panggung yang sama untuk SEMUA stage,
/// dengan gambar hadiah yang dideteksi otomatis — file transparan
/// (PNG cutout) tampil sebagai OBJEK di atas panggung navy-emas,
/// sedangkan foto biasa (JPG/poster) menjadi LATAR penuh layar.
/// Header selalu terang + scrim atas agar terbaca di foto apa pun.
///
/// Semua ukuran ditulis untuk kanvas 1920x1080 (mockup 960x540 ×2)
/// lalu dikali faktor skala responsif [audienceScaleFor].
///
/// CATATAN: agar plugin (window_manager) terdaftar di sub-window pada
/// build Windows, ikuti langkah registrasi plugin di README (edit
/// windows/runner/flutter_window.cpp sekali saja).
class AudienceApp extends StatefulWidget {
  const AudienceApp({super.key});

  @override
  State<AudienceApp> createState() => _AudienceAppState();
}

enum _Stage { idle, shuffle, winner, rejected, notFound }

/// Faktor skala responsif untuk layar penonton: 1.0 pada 1920x1080,
/// mengecil di proyektor 720p, membesar di 4K (dibatasi 0.5–1.6).
double audienceScaleFor(Size size) {
  final s = size.width / 1920 < size.height / 1080
      ? size.width / 1920
      : size.height / 1080;
  return s.clamp(0.5, 1.6);
}

double audienceScale(BuildContext context) =>
    audienceScaleFor(MediaQuery.sizeOf(context));

/// Palet layout broadcast navy-emas (hex persis dari mockup).
class _Bc {
  static const Color navy = AudienceTheme.navy800; // #10224D
  static const Color navyDeep = AudienceTheme.navy900; // #0A1633
  static const Color deep = Color(0xFF060C1F);
  static const Color gold = AudienceTheme.gold; // #D4AF37
  static const Color goldLight = AudienceTheme.goldLight; // #F3D27A
  static const Color onGold = Color(0xFF3A2E00);
  static const Color onGoldDim = Color(0xFF7A5E10);
  static const Color muted = Color(0xFFC6CEDE);
  static const Color tagline = Color(0xFFD7E7FF);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberLight = Color(0xFFFCD34D);
}

class _AudienceAppState extends State<AudienceApp> with WindowListener {
  _Stage _stage = _Stage.idle;
  String _coupon = '';
  String _nama = '';
  String _alamat = '';
  String _gambar = '';
  String _hadiah = '';
  // Hadiah yang sedang diundi (untuk panel hadiah kiri). Terpisah dari
  // _hadiah karena showRejected menimpa _hadiah dengan nama hadiah
  // yang SEBELUMNYA dimenangkan pemilik kupon.
  String _prize = '';
  String _rejectedRekening = '';
  String _rejectedWaktu = '';
  String _rolling = '000000';
  Timer? _rollTimer;
  final _rand = Random();

  // --- Deteksi otomatis mode gambar hadiah ---
  // File transparan (PNG cutout) -> objek di panggung; foto biasa ->
  // latar penuh. Hasil dideteksi SEKALI per path (async, tidak blokir
  // frame) dan di-cache; selama deteksi berjalan dipakai mode latar.
  final Map<String, bool> _cutoutCache = {};
  String? _detectingPath;
  bool _isCutout = false;

  void _updateImageMode(String path) {
    if (path.isEmpty || !File(path).existsSync()) {
      _detectingPath = null;
      if (_isCutout) setState(() => _isCutout = false);
      return;
    }
    final cached = _cutoutCache[path];
    if (cached != null) {
      _detectingPath = null;
      if (_isCutout != cached) setState(() => _isCutout = cached);
      return;
    }
    _detectingPath = path;
    if (_isCutout) setState(() => _isCutout = false);
    _detectTransparency(path).then((result) {
      // Abaikan hasil usang: hanya terapkan bila path masih sama
      // dengan yang sedang tampil & sedang dideteksi.
      if (!mounted || _detectingPath != path || _gambar != path) return;
      _cutoutCache[path] = result;
      _detectingPath = null;
      if (_isCutout != result) setState(() => _isCutout = result);
    });
  }

  /// Dekode file gambar dan hitung fraksi piksel dengan alpha < 250.
  /// Cutout bila fraksi > 1%. Yang menentukan adalah ISI alpha-nya,
  /// bukan ekstensi file (PNG yang sepenuhnya opaque = latar).
  Future<bool> _detectTransparency(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image
              .toByteData(format: ui.ImageByteFormat.rawRgba);
          if (data == null) return false;
          final b = data.buffer
              .asUint8List(data.offsetInBytes, data.lengthInBytes);
          var transparent = 0;
          final total = b.length ~/ 4;
          for (var i = 3; i < b.length; i += 4) {
            if (b[i] < 250) transparent++;
          }
          return total > 0 && transparent / total > 0.01;
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return false;
    }
  }

  static const _channel = WindowMethodChannel(
    AudienceProtocol.channelName,
    mode: ChannelMode.bidirectional,
  );

  @override
  void initState() {
    super.initState();
    _goFullscreen();
    _channel.setMethodCallHandler(_onMethod);
    windowManager.addListener(this);
    // Suara TIDAK lagi diputar dari window ini (audioplayers terbukti
    // bisu di sub-window). Pemutaran pindah ke window operator.
    // Di sini cukup self-test sekali + laporkan hasilnya ke operator
    // agar penyebab bisunya terlihat (diagnostik).
    _runSoundSelfTest();
  }

  Future<void> _runSoundSelfTest() async {
    final err = await Sounds.selfTest();
    try {
      await _channel.invokeMethod(AudienceProtocol.soundReport, {
        AudienceProtocol.argDetail: err ?? 'ok',
      });
    } catch (_) {
      // Operator belum siap menerima — abaikan.
    }
  }

  Future<void> _goFullscreen() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle('PT. BPR Bank Bulungan - Layar Penonton');
      // Otomatis pindah ke monitor kedua (proyektor) bila ada;
      // kalau cuma 1 monitor, tetap fullscreen di monitor utama.
      try {
        final displays = await screenRetriever.getAllDisplays();
        if (displays.length > 1) {
          final pos = displays[1].visiblePosition;
          if (pos != null) await windowManager.setPosition(pos);
        }
      } catch (_) {}
      await windowManager.setFullScreen(true);
      // Cegah window penonton tertutup tidak sengaja (mis. Alt+F4):
      // percobaan tutup diubah jadi sembunyikan saja (lihat onWindowClose).
      await windowManager.setPreventClose(true);
    } catch (_) {
      // Plugin belum teregistrasi di sub-window (lihat README).
      // Window tetap jalan sebagai window biasa.
    }
  }

  /// Alt+F4 / tombol tutup JANGAN menghancurkan window penonton —
  /// sembunyikan saja supaya operator bisa membukanya kembali instan
  /// (state tampilan tetap terjaga) via "Buka Layar Penonton".
  /// Operator diberi tahu agar statusnya akurat.
  @override
  void onWindowClose() async {
    try {
      await windowManager.hide();
    } catch (_) {}
    try {
      await _channel.invokeMethod(AudienceProtocol.audienceHidden);
    } catch (_) {}
  }

  Future<dynamic> _onMethod(MethodCall call) async {
    switch (call.method) {
      case AudienceProtocol.showIdle:
        _stopRoll();
        setState(() => _stage = _Stage.idle);
        break;
      case AudienceProtocol.startShuffle:
        setState(() {
          _stage = _Stage.shuffle;
          final a = (call.arguments as Map?) ?? {};
          final prize = a[AudienceProtocol.argHadiah];
          if (prize is String && prize.isNotEmpty) _hadiah = prize;
          _gambar = (a[AudienceProtocol.argGambar] ?? '').toString();
          _prize = _hadiah;
        });
        _updateImageMode(_gambar);
        _startRoll();
        break;
      case AudienceProtocol.stopShuffle:
        _stopRoll();
        break;
      case AudienceProtocol.showWinner:
        _stopRoll();
        final args = (call.arguments as Map?) ?? {};
        setState(() {
          _coupon = (args[AudienceProtocol.argCoupon] ?? '').toString();
          _nama = (args[AudienceProtocol.argNama] ?? '').toString();
          _alamat = (args[AudienceProtocol.argAlamat] ?? '').toString();
          _gambar = (args[AudienceProtocol.argGambar] ?? '').toString();
          _hadiah = (args[AudienceProtocol.argHadiah] ?? '').toString();
          _prize = _hadiah;
          _stage = _Stage.winner;
        });
        _updateImageMode(_gambar);
        break;
      case AudienceProtocol.showPrize:
        final args = (call.arguments as Map?) ?? {};
        setState(() {
          _hadiah = (args[AudienceProtocol.argHadiah] ?? '').toString();
          _gambar = (args[AudienceProtocol.argGambar] ?? '').toString();
          _prize = _hadiah;
          // Hadiah baru = undian sebelumnya selesai → kembali ke idle,
          // kecuali sedang mengocok (mode random).
          if (_stage != _Stage.shuffle) _stage = _Stage.idle;
        });
        _updateImageMode(_gambar);
        break;
      case AudienceProtocol.showRejected:
        _stopRoll();
        final rejArgs = (call.arguments as Map?) ?? {};
        setState(() {
          _coupon = (rejArgs[AudienceProtocol.argCoupon] ?? '').toString();
          _nama = (rejArgs[AudienceProtocol.argNama] ?? '').toString();
          _rejectedRekening =
              (rejArgs[AudienceProtocol.argRekening] ?? '').toString();
          _hadiah = (rejArgs[AudienceProtocol.argHadiah] ?? '').toString();
          _rejectedWaktu =
              (rejArgs[AudienceProtocol.argWaktu] ?? '').toString();
          _stage = _Stage.rejected;
        });
        // Sengaja tanpa bunyi fanfare & tanpa confetti — ini peringatan,
        // bukan perayaan.
        break;
      case AudienceProtocol.showNotFound:
        _stopRoll();
        final nfArgs = (call.arguments as Map?) ?? {};
        setState(() {
          _coupon = (nfArgs[AudienceProtocol.argCoupon] ?? '').toString();
          _stage = _Stage.notFound;
        });
        // Tanpa fanfare & confetti — hanya info validasi.
        break;
      case AudienceProtocol.audienceMute:
        final args = (call.arguments as Map?) ?? {};
        final m = args[AudienceProtocol.argMuted];
        Sounds.setMuted(m is bool ? m : m.toString() == 'true');
        break;
    }
    return null;
  }

  void _startRoll() {
    _stopRoll();
    _rollTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (mounted) {
        setState(() {
          _rolling = _rand.nextInt(1000000).toString().padLeft(6, '0');
        });
        // Roll berjalan senyap; suara hanya pada reveal pemenang dan
        // diputar oleh window operator (lihat Sounds.playReveal) —
        // bukan dari sub-window ini.
      }
    });
  }

  void _stopRoll() {
    _rollTimer?.cancel();
    _rollTimer = null;
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _stopRoll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = audienceScale(context);
    // SATU gaya imersif untuk semua stage. Gambar hadiah yang
    // terdeteksi transparan (cutout) menjadi objek di panggung;
    // foto biasa menjadi latar penuh; tanpa foto = latar navy-emas.
    // Komposisi (header, panel kanan, blok kiri bawah) tidak pernah
    // berubah — hanya isinya yang berganti.
    final hasPhoto = _gambar.isNotEmpty && File(_gambar).existsSync();
    final cutout = hasPhoto && _isCutout;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          children: [
            if (cutout)
              _CutoutStage(path: _gambar, scale: s)
            else if (hasPhoto)
              _ImmersiveBackground(path: _gambar)
            else
              _BroadcastBackground(scale: s),
            // Scrim atas: di atas latar/objek, di bawah panel & header
            // (z-order mock final: scrim 3, panel 4, header 5).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 260 * s,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x8C060C1F), Color(0x00060C1F)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 52 * s,
              right: 52 * s,
              top: 208 * s,
              bottom: 52 * s,
              child: _bodyZone(s),
            ),
            Positioned(
              top: 40 * s,
              left: 52 * s,
              right: 52 * s,
              child: _Header(scale: s),
            ),
          ],
        ),
      ),
    );
  }

  /// Zona konten di bawah header: panel info kaca SELALU di kanan,
  /// blok teks SELALU di kiri bawah — posisi & bentuk tetap di semua
  /// stage (satu gaya imersif), yang berubah hanya isinya.
  Widget _bodyZone(double s) {
    if (_stage == _Stage.winner) {
      return _WinnerReveal(
        key: ValueKey('winner-$_coupon'),
        coupon: _coupon,
        nama: _nama,
        alamat: _alamat,
        hadiah: _hadiah,
        scale: s,
      );
    }
    return Stack(
      children: [
        Positioned(right: 0, top: 0, bottom: 0, child: _panelForStage(s)),
        Positioned(
          left: 16 * s,
          bottom: 24 * s,
          child: _blockForStage(s),
        ),
      ],
    );
  }

  /// Panel info kanan per stage (stage winner ditangani _WinnerReveal).
  Widget _panelForStage(double s) {
    switch (_stage) {
      case _Stage.idle:
        return _InfoPanel(
          scale: s,
          numText: '— — — — — —',
          mode: _InfoMode.menunggu,
        );
      case _Stage.shuffle:
        return _InfoPanel(
          scale: s,
          numLabel: 'NOMOR KUPON',
          numText: _rolling,
          mode: _InfoMode.menunggu,
          waitingText: 'Sedang mengundi…',
        );
      case _Stage.rejected:
        return _InfoPanel(
          scale: s,
          numText: _coupon,
          mode: _InfoMode.rejected,
          nama: _nama,
          rejectedLine: _rejectedLine(),
        );
      case _Stage.notFound:
        return _InfoPanel(
          scale: s,
          numText: _coupon,
          mode: _InfoMode.notFound,
        );
      case _Stage.winner:
        // Tidak pernah tercapai: winner dirender oleh _WinnerReveal.
        return const SizedBox.shrink();
    }
  }

  /// Blok kiri-bawah per stage (stage winner ditangani _WinnerReveal):
  /// pill label + baris-baris teks ber-shadow menimpa latar panggung.
  Widget _blockForStage(double s) {
    final shadows = [
      Shadow(
        color: const Color(0x99000000),
        blurRadius: 14 * s,
        offset: Offset(0, 3 * s),
      ),
    ];
    TextStyle small(Color c) => TextStyle(
          fontSize: 26 * s,
          fontWeight: FontWeight.bold,
          letterSpacing: 3 * s,
          color: c,
          shadows: shadows,
        );
    TextStyle bigNumber(Color c) => TextStyle(
          fontSize: 68 * s,
          fontWeight: FontWeight.w900,
          color: c,
          shadows: shadows,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    TextStyle prizeName(double size) => TextStyle(
          fontSize: size * s,
          fontWeight: FontWeight.w900,
          color: _Bc.goldLight,
          shadows: shadows,
        );
    switch (_stage) {
      case _Stage.idle:
        if (_prize.isEmpty) {
          return _blockShell(s, [
            _stagePill(s, text: 'PENGUNDIAN HADIAH'),
            SizedBox(height: 20 * s),
            Text(
              'SEGERA DIMULAI',
              style: TextStyle(
                fontSize: 68 * s,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                shadows: shadows,
              ),
            ),
          ]);
        }
        return _blockShell(s, [
          _stagePill(s, text: 'HADIAH'),
          SizedBox(height: 20 * s),
          Text('SEDANG DIUNDI', style: small(Colors.white)),
          Text(
            _prize.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: prizeName(60).copyWith(height: 1.25),
          ),
        ]);
      case _Stage.shuffle:
        return _blockShell(s, [
          _stagePill(s, text: 'SEDANG DIUNDI'),
          SizedBox(height: 20 * s),
          Text('NOMOR KUPON', style: small(_Bc.goldLight)),
          Text(_rolling, style: bigNumber(Colors.white)),
          if (_prize.isNotEmpty) ...[
            SizedBox(height: 14 * s),
            Text(
              _prize.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: prizeName(50),
            ),
          ],
        ]);
      case _Stage.rejected:
        return _blockShell(s, [
          _stagePill(s,
              text: 'SUDAH PERNAH MENANG',
              icon: Icons.warning_amber,
              amber: true),
          SizedBox(height: 20 * s),
          Text('NOMOR KUPON', style: small(_Bc.amberLight)),
          Text(_coupon, style: bigNumber(Colors.white)),
          if (_prize.isNotEmpty) ...[
            SizedBox(height: 14 * s),
            Text(
              _prize.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: prizeName(50),
            ),
          ],
        ]);
      case _Stage.notFound:
        return _blockShell(s, [
          _stagePill(s,
              text: 'TIDAK TERDAFTAR',
              icon: Icons.warning_amber,
              amber: true),
          SizedBox(height: 20 * s),
          Text('NOMOR KUPON', style: small(_Bc.amberLight)),
          Text(_coupon, style: bigNumber(Colors.white)),
          SizedBox(height: 14 * s),
          Text(
            'Mohon periksa kembali ke petugas',
            style: TextStyle(
              fontSize: 26 * s,
              color: Colors.white,
              shadows: shadows,
            ),
          ),
        ]);
      case _Stage.winner:
        // Tidak pernah tercapai: winner dirender oleh _WinnerReveal.
        return const SizedBox.shrink();
    }
  }

  /// Kerangka blok kiri-bawah: lebar 960 (mockup) dibungkus FittedBox
  /// scaleDown agar tidak pernah menabrak panel kanan; teks di
  /// dalamnya tetap bisa membungkus (maks 2 baris untuk nama hadiah).
  Widget _blockShell(double s, List<Widget> children) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 960 * s),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomLeft,
        child: SizedBox(
          width: 960 * s,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }

  /// Pill label blok kiri-bawah: gradient emas (amber untuk
  /// peringatan), teks gelap w900, ikon opsional di depan teks.
  Widget _stagePill(double s,
      {required String text, IconData? icon, bool amber = false}) {
    final onPill = amber ? const Color(0xFF451A03) : _Bc.onGold;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 40 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: amber
              ? const [Color(0xFFFBBF24), _Bc.amber]
              : const [_Bc.goldLight, _Bc.gold],
        ),
        borderRadius: BorderRadius.circular(14 * s),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 30 * s, color: onPill),
            SizedBox(width: 10 * s),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 28 * s,
              fontWeight: FontWeight.w900,
              color: onPill,
            ),
          ),
        ],
      ),
    );
  }

  /// Baris info penolakan di panel info: hadiah yang sebelumnya
  /// dimenangkan pemilik kupon + waktunya.
  String _rejectedLine() {
    final parts = <String>[
      if (_hadiah.isNotEmpty) 'Sudah memenangkan: $_hadiah',
      if (_rejectedWaktu.isNotEmpty) _rejectedWaktu,
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    if (_rejectedRekening.isNotEmpty) return 'Rek. $_rejectedRekening';
    return 'Sudah pernah memenangkan hadiah';
  }
}

/// Background panggung tanpa foto: gradient navy 150° + glow radial
/// emas kanan-atas & kiri-bawah + watermark piala samar di kiri +
/// gelombang emas sangat halus. Dipakai ulang oleh _CutoutStage
/// (tanpa watermark, gelombang lebih nyata).
class _BroadcastBackground extends StatelessWidget {
  final double scale;
  final bool watermark;
  final int? waveAlpha;
  const _BroadcastBackground({
    required this.scale,
    this.watermark = true,
    this.waveAlpha,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.5, -0.87),
              end: Alignment(0.5, 0.87),
              colors: [_Bc.navy, _Bc.navyDeep, _Bc.deep],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -260 * s,
          right: -160 * s,
          child: _Blur(color: const Color(0x29D4AF37), size: 720 * s),
        ),
        Positioned(
          bottom: -260 * s,
          left: -160 * s,
          child: _Blur(color: const Color(0x1AD4AF37), size: 720 * s),
        ),
        // Watermark piala samar di kiri (mockup satu-gaya layar 4).
        // Tidak dipakai di mode cutout (objek menempati area kiri).
        if (watermark)
          Positioned(
            left: 180 * s,
            top: 300 * s,
            child: Icon(
              Icons.emoji_events,
              size: 500 * s,
              color: const Color(0x24D4AF37),
            ),
          ),
        Positioned.fill(
          child: CustomPaint(
            painter: _WavesPainter(
              alphaBottom: waveAlpha ?? 0x1F,
              alphaTop: waveAlpha ?? 0x1A,
            ),
          ),
        ),
      ],
    );
  }
}

/// Panggung mode cutout: latar navy-emas + gelombang emas 0x29 +
/// spotlight putih di belakang objek + objek transparan (contain)
/// di kiri-tengah. Tidak ada shade horizontal (panel kaca sudah
/// cukup pekat) dan tidak ada watermark piala.
class _CutoutStage extends StatelessWidget {
  final String path;
  final double scale;
  const _CutoutStage({required this.path, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final size = MediaQuery.sizeOf(context);
    final sw = 960 * s;
    final sh = 760 * s;
    return Stack(
      fit: StackFit.expand,
      children: [
        _BroadcastBackground(scale: s, watermark: false, waveAlpha: 0x29),
        // Spotlight elips di belakang objek (pusat 32% lebar,
        // 55% tinggi; putih alpha 0.20 memudar ke 0 di 65% radius).
        Positioned(
          left: size.width * 0.32 - sw / 2,
          top: size.height * 0.55 - sh / 2,
          child: Container(
            width: sw,
            height: sh,
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.all(Radius.elliptical(sw / 2, sh / 2)),
              gradient: const RadialGradient(
                colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
                stops: [0.0, 0.65],
              ),
            ),
          ),
        ),
        // Objek: contain (utuh, tidak terpotong), kiri -20, atas 192,
        // tinggi 800 — persis mockup-hadiah-final (960x540 ×2).
        Positioned(
          left: -20 * s,
          top: 192 * s,
          height: 800 * s,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// Background panggung berfoto: foto hadiah memenuhi layar +
/// layer shade navy horizontal (transparan di kiri → pekat di kanan)
/// persis mockup satu-gaya.
class _ImmersiveBackground extends StatelessWidget {
  final String path;
  const _ImmersiveBackground({required this.path});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(color: _Bc.navyDeep),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0x00000000),
                Color(0x9E0A1633),
                Color(0xEB060C1F),
              ],
              stops: [0.32, 0.63, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

/// Gelombang emas halus di atas & bawah layar, meniru path SVG
/// mockup (kanvas 960x540, diskalakan proporsional ke ukuran layar).
class _WavesPainter extends CustomPainter {
  final int alphaBottom;
  final int alphaTop;
  const _WavesPainter({this.alphaBottom = 0x1F, this.alphaTop = 0x1A});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 960;
    final sy = size.height / 540;
    double x(double v) => v * sx;
    double y(double v) => v * sy;

    final bottom = Path()
      ..moveTo(x(0), y(420))
      ..cubicTo(x(240), y(340), x(420), y(500), x(700), y(420))
      ..cubicTo(x(820), y(385), x(900), y(420), x(960), y(395))
      ..lineTo(x(960), y(540))
      ..lineTo(x(0), y(540))
      ..close();
    canvas.drawPath(
        bottom, Paint()..color = Color(0xFFD4AF37).withAlpha(alphaBottom));

    final top = Path()
      ..moveTo(x(0), y(90))
      ..cubicTo(x(200), y(40), x(420), y(130), x(680), y(80))
      ..cubicTo(x(810), y(55), x(900), y(80), x(960), y(60))
      ..lineTo(x(960), y(0))
      ..lineTo(x(0), y(0))
      ..close();
    canvas.drawPath(top, Paint()..color = Color(0xFFD4AF37).withAlpha(alphaTop));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Lingkaran cahaya radial lembut (glow emas di background).
class _Blur extends StatelessWidget {
  final Color color;
  final double size;
  const _Blur({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, const Color(0x00000000)]),
      ),
    );
  }
}

/// Header semua layar: brand bank di kiri, judul acara di kanan.
/// SELALU terang (PT emas, nama putih + shadow, tagline terang) —
/// varian teks gelap dihapus: dengan scrim atas + header terang,
/// header terbaca di latar foto apa pun (terang maupun gelap).
class _Header extends StatelessWidget {
  final double scale;
  const _Header({required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo placeholder: kotak gradient hijau-biru + huruf "B".
        // Diganti file logo asli bank bila sudah tersedia.
        Container(
          width: 104 * s,
          height: 104 * s,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7ED957), Color(0xFF0E9F6E), Color(0xFF1565C0)],
              stops: [0.0, 0.45, 1.0],
            ),
            borderRadius: BorderRadius.circular(24 * s),
            boxShadow: [
              BoxShadow(
                color: const Color(0x59000000),
                blurRadius: 28 * s,
                offset: Offset(0, 8 * s),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'B',
              style: TextStyle(
                fontSize: 64 * s,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: Colors.white,
              ),
            ),
          ),
        ),
        SizedBox(width: 24 * s),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PT. BPR',
              style: TextStyle(
                fontSize: 24 * s,
                fontWeight: FontWeight.bold,
                letterSpacing: 2 * s,
                color: _Bc.goldLight,
              ),
            ),
            Text(
              'BANK BULUNGAN',
              style: TextStyle(
                fontSize: 48 * s,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5 * s,
                height: 1.05,
                color: Colors.white,
              ),
            ),
            Text(
              'Mitra Terpercaya Membangun Masa Depan',
              style: TextStyle(
                fontSize: 23 * s,
                fontStyle: FontStyle.italic,
                color: _Bc.tagline,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Judul acara rata kanan penuh, segaris dengan tepi kanan
        // panel info di bawahnya.
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'PENGUNDIAN HADIAH',
              style: TextStyle(
                fontSize: 42 * s,
                fontWeight: FontWeight.w900,
                letterSpacing: 1 * s,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: const Color(0x66000000),
                    blurRadius: 10 * s,
                    offset: Offset(0, 2 * s),
                  ),
                ],
              ),
            ),
            Text(
              'Nasabah Setia Bank Bulungan',
              style: TextStyle(
                fontSize: 31 * s,
                fontWeight: FontWeight.bold,
                color: _Bc.goldLight,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

enum _InfoMode { menunggu, winner, rejected, notFound }

/// Panel info kaca (kanan, selalu ada di semua stage): numbox emas,
/// bar PEMENANG, kotak pemenang, dan teks script pemenang di bawah
/// (khusus stage winner; stage lain berakhir setelah kotak pemenang).
class _InfoPanel extends StatelessWidget {
  final double scale;
  final String numLabel;
  final String numText;
  final String waitingText;
  final _InfoMode mode;
  final String nama;
  final String alamat;
  final String rejectedLine;

  /// Progres animasi munculnya kartu nama pemenang (0..1).
  final double winnerReveal;

  /// Progres animasi munculnya teks "Selamat Kepada Pemenang!" (0..1).
  final double scriptReveal;

  const _InfoPanel({
    required this.scale,
    required this.numText,
    required this.mode,
    this.numLabel = 'NOMOR KUPON PEMENANG',
    this.waitingText = 'Menunggu pengundian…',
    this.nama = '',
    this.alamat = '',
    this.rejectedLine = '',
    this.winnerReveal = 1,
    this.scriptReveal = 1,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      width: 544 * s,
      padding: EdgeInsets.all(28 * s),
      decoration: BoxDecoration(
        color: const Color(0xC70A1633),
        border: Border.all(
          color: const Color(0xBFD4AF37),
          width: 1.5 * s,
        ),
        borderRadius: BorderRadius.circular(28 * s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Numbox adalah elemen pertama panel; jarak 20 dari tepi
          // atas panel mengikuti margin-top numbox pada mockup
          // bersih (10px pada skala mockup ×2).
          SizedBox(height: 20 * s),
          // Numbox: label kecil DI DALAM kotak, di atas angka.
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: 12 * s, vertical: 16 * s),
            decoration: BoxDecoration(
              color: _Bc.goldLight,
              borderRadius: BorderRadius.circular(18 * s),
            ),
            child: Column(
              children: [
                Text(
                  numLabel,
                  style: TextStyle(
                    fontSize: 18 * s,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3 * s,
                    color: _Bc.onGoldDim,
                  ),
                ),
                SizedBox(height: 4 * s),
                Text(
                  numText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 54 * s,
                    fontWeight: FontWeight.w900,
                    color: _Bc.navy,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 24 * s),
          Container(
            padding: EdgeInsets.symmetric(vertical: 10 * s),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_Bc.goldLight, _Bc.gold],
              ),
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(16 * s)),
            ),
            child: Text(
              'PEMENANG',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28 * s,
                fontWeight: FontWeight.w900,
                letterSpacing: 2 * s,
                color: _Bc.onGold,
              ),
            ),
          ),
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: 24 * s, vertical: 20 * s),
            decoration: BoxDecoration(
              color: const Color(0x99060C1F),
              border: Border(
                left: BorderSide(color: _Bc.gold, width: 1.5 * s),
                right: BorderSide(color: _Bc.gold, width: 1.5 * s),
                bottom: BorderSide(color: _Bc.gold, width: 1.5 * s),
              ),
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(16 * s)),
            ),
            child: _winboxContent(s),
          ),
          const Spacer(),
          _bottomText(s),
        ],
      ),
    );
  }

  Widget _avatar(double s, IconData icon) {
    return Container(
      width: 76 * s,
      height: 76 * s,
      decoration:
          const BoxDecoration(shape: BoxShape.circle, color: _Bc.goldLight),
      child: Icon(icon, size: 40 * s, color: _Bc.navy),
    );
  }

  Widget _winboxContent(double s) {
    switch (mode) {
      case _InfoMode.menunggu:
        return Row(
          children: [
            _avatar(s, Icons.person),
            SizedBox(width: 20 * s),
            Expanded(
              child: Text(
                waitingText,
                style: TextStyle(
                  fontSize: 27 * s,
                  fontWeight: FontWeight.w600,
                  color: _Bc.muted,
                ),
              ),
            ),
          ],
        );
      case _InfoMode.notFound:
        return Row(
          children: [
            _avatar(s, Icons.search_off),
            SizedBox(width: 20 * s),
            Expanded(
              child: Text(
                'Nomor tidak ditemukan di data nasabah',
                style: TextStyle(fontSize: 24 * s, color: _Bc.muted),
              ),
            ),
          ],
        );
      case _InfoMode.rejected:
        return Row(
          children: [
            _avatar(s, Icons.person),
            SizedBox(width: 20 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nama,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 33 * s,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 4 * s),
                  Text(
                    rejectedLine,
                    style: TextStyle(fontSize: 21 * s, color: _Bc.muted),
                  ),
                ],
              ),
            ),
          ],
        );
      case _InfoMode.winner:
        if (winnerReveal <= 0) {
          return Row(
            children: [
              _avatar(s, Icons.person),
              SizedBox(width: 20 * s),
              Expanded(
                child: Text(
                  'Mengumumkan pemenang…',
                  style: TextStyle(fontSize: 24 * s, color: _Bc.muted),
                ),
              ),
            ],
          );
        }
        return Opacity(
          opacity: winnerReveal,
          child: Transform.scale(
            scale: 0.6 + 0.4 * winnerReveal,
            child: Row(
              children: [
                _avatar(s, Icons.person),
                SizedBox(width: 20 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nama,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 33 * s,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (alamat.trim().isNotEmpty) ...[
                        SizedBox(height: 4 * s),
                        Text(
                          alamat,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 21 * s, color: _Bc.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _bottomText(double s) {
    if (mode == _InfoMode.winner && scriptReveal > 0) {
      return Opacity(
        opacity: scriptReveal,
        child: Text(
          'Selamat\nKepada Pemenang!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 46 * s,
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
            height: 1.25,
            color: _Bc.goldLight,
          ),
        ),
      );
    }
    // Stage non-winner: panel berakhir setelah kotak pemenang —
    // tidak ada teks pengisi di bagian bawah (mockup bersih).
    return const SizedBox.shrink();
  }
}

/// Scene pengumuman pemenang: nomor ng-roll ala mesin slot 2,6 detik
/// (easeOutQuart, 45 frame — pola yang sama seperti sebelumnya), lalu
/// mengunci, kartu nama muncul, dan hujan confetti.
///
/// Memakai panggung yang sama seperti stage lain: blok nomor/nama/
/// hadiah di kiri bawah menimpa latar (nomor ikut ng-roll di blok
/// kiri + numbox panel kanan), panel info kaca di kanan.
class _WinnerReveal extends StatefulWidget {
  final String coupon;
  final String nama;
  final String alamat;
  final String hadiah;
  final double scale;

  const _WinnerReveal({
    super.key,
    required this.coupon,
    required this.nama,
    required this.alamat,
    required this.hadiah,
    required this.scale,
  });

  @override
  State<_WinnerReveal> createState() => _WinnerRevealState();
}

class _WinnerRevealState extends State<_WinnerReveal>
    with TickerProviderStateMixin {
  late final AnimationController _roll; // slot-machine nomor (2.6 dtk)
  late final CurvedAnimation _rollCurve; // easeOut = melambat di akhir
  late final AnimationController _reveal; // kartu nama + confetti
  late final CurvedAnimation _nameCurve;
  late final CurvedAnimation _scriptCurve;
  late final List<_Confetti> _pieces;
  final _rand = Random();
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _roll = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600));
    _rollCurve = CurvedAnimation(parent: _roll, curve: Curves.easeOutQuart);
    _reveal = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4500));
    _nameCurve = CurvedAnimation(
        parent: _reveal, curve: const Interval(0.1, 0.35));
    _scriptCurve = CurvedAnimation(
        parent: _reveal, curve: const Interval(0.35, 0.55));
    _roll.addStatusListener((st) {
      if (st == AnimationStatus.completed && mounted) {
        setState(() => _locked = true);
        // Fanfare diputar oleh window operator (sinkron via playReveal).
        _reveal.forward();
      }
    });
    // Catatan: roll berjalan SENYAP total — window operator hanya
    // menjadwalkan fanfare di ujung roll ini (Sounds.playReveal,
    // 2,6 dtk), tanpa tick sama sekali.
    _pieces = List.generate(90, (_) => _Confetti.random(_rand));
    _roll.forward();
  }

  @override
  void dispose() {
    _roll.dispose();
    _reveal.dispose();
    super.dispose();
  }

  /// Nomor acak semu per tick (deterministik agar stabil per frame).
  String _rollNumber(int tick) {
    final len = widget.coupon.length;
    var max = 1;
    for (var i = 0; i < len; i++) {
      max *= 10;
    }
    final n = Random(tick * 7919 + 13).nextInt(max);
    return n.toString().padLeft(len, '0');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return AnimatedBuilder(
      animation: Listenable.merge([_roll, _reveal]),
      builder: (context, _) {
        final tick = (_rollCurve.value * 45).floor();
        final display = _locked ? widget.coupon : _rollNumber(tick);
        final info = _InfoPanel(
          scale: s,
          numText: display,
          mode: _InfoMode.winner,
          nama: widget.nama,
          alamat: widget.alamat,
          winnerReveal: _locked ? _nameCurve.value : 0,
          scriptReveal: _locked ? _scriptCurve.value : 0,
        );
        return Stack(
          children: [
            Positioned(
              left: 16 * s,
              bottom: 24 * s,
              child: _winnerBlock(s, display),
            ),
            Positioned(right: 0, top: 0, bottom: 0, child: info),
            // Confetti menutupi zona konten penuh di bawah header
            // (dipertahankan dari tampilan lama; mulai setelah nomor
            // mengunci).
            Positioned.fill(
              child: CustomPaint(painter: _ConfettiPainter(_reveal, _pieces)),
            ),
          ],
        );
      },
    );
  }

  /// Blok kiri-bawah stage pemenang (mockup satu-gaya layar 3): pill
  /// PEMENANG, label nomor kupon, nama pemenang, nama hadiah — semua
  /// menimpa latar dengan shadow. Selama nomor masih ng-roll, yang
  /// tampil angka berjalannya; nama & hadiah muncul setelah mengunci.
  Widget _winnerBlock(double s, String display) {
    final shadows = [
      Shadow(
        color: const Color(0x99000000),
        blurRadius: 14 * s,
        offset: Offset(0, 3 * s),
      ),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 960 * s),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.bottomLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 40 * s, vertical: 10 * s),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_Bc.goldLight, _Bc.gold],
                ),
                borderRadius: BorderRadius.circular(14 * s),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events, size: 30 * s, color: _Bc.onGold),
                  SizedBox(width: 10 * s),
                  Text(
                    'PEMENANG',
                    style: TextStyle(
                      fontSize: 28 * s,
                      fontWeight: FontWeight.w900,
                      color: _Bc.onGold,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20 * s),
            if (!_locked)
              Text(
                display,
                style: TextStyle(
                  fontSize: 68 * s,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: shadows,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              )
            else ...[
              Text(
                'NOMOR KUPON ${widget.coupon}',
                style: TextStyle(
                  fontSize: 26 * s,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3 * s,
                  color: _Bc.goldLight,
                  shadows: shadows,
                ),
              ),
              SizedBox(height: 10 * s),
              Opacity(
                opacity: _nameCurve.value,
                child: Text(
                  widget.nama.toUpperCase(),
                  style: TextStyle(
                    fontSize: 68 * s,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    shadows: shadows,
                  ),
                ),
              ),
              SizedBox(height: 6 * s),
              Opacity(
                opacity: _scriptCurve.value,
                child: Text(
                  widget.hadiah.toUpperCase(),
                  style: TextStyle(
                    fontSize: 50 * s,
                    fontWeight: FontWeight.w900,
                    color: _Bc.goldLight,
                    shadows: shadows,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Satu potong confetti.
class _Confetti {
  double x0, y0, speed, size, phase, swayFreq, rotSpeed;
  Color color;

  _Confetti.random(Random r)
      : x0 = r.nextDouble(),
        y0 = -0.2 + r.nextDouble() * 0.4,
        speed = 0.9 + r.nextDouble() * 0.9,
        size = 6 + r.nextDouble() * 10,
        phase = r.nextDouble(),
        swayFreq = 0.8 + r.nextDouble() * 1.6,
        rotSpeed = 1 + r.nextDouble() * 3,
        color = [
          const Color(0xFFD4AF37),
          const Color(0xFFFFF3C4),
          const Color(0xFFFFD700),
          const Color(0xFFFFFFFF),
          const Color(0xFF2A4A8F),
        ][r.nextInt(5)];
}

class _ConfettiPainter extends CustomPainter {
  final AnimationController controller;
  final List<_Confetti> pieces;

  _ConfettiPainter(this.controller, this.pieces) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final t = controller.value;
    if (t <= 0) return; // belum mulai reveal (masih fase roll nomor)
    final paint = Paint();
    for (final c in pieces) {
      final yFrac = (c.y0 + t * c.speed) % 1.35;
      final y = (yFrac - 0.18) * size.height;
      final x = c.x0 * size.width +
          sin(t * 6.28318 * c.swayFreq + c.phase * 6.28318) * 34;
      final fade = (1 - t * t).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(c.phase * 6.28318 + t * c.rotSpeed * 6.28318);
      paint.color = c.color.withValues(alpha: 0.95 * fade);
      canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: c.size, height: c.size * 0.62),
          paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
