import 'dart:async';
import 'dart:io';
import 'dart:math';

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
/// Layout mengikuti mockup broadcast navy-emas yang disetujui Gugun
/// (mockup-layout-broadcast-v3v4.html varian 4; layar pemenang imersif
/// dari mockup-layout-gabungan.html): header brand + judul + badge
/// LIVE, tiga kolom (panel hadiah | drum mesin undi | panel info).
/// Stage pemenang dengan foto hadiah valid tampil imersif: foto
/// memenuhi layar, panel info kaca melayang di kanan.
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
  static const Color goldDark = AudienceTheme.goldDark; // #9C7C1E
  static const Color onGold = Color(0xFF3A2E00);
  static const Color onGoldDim = Color(0xFF7A5E10);
  static const Color muted = Color(0xFFC6CEDE);
  static const Color tagline = Color(0xFFD7E7FF);
  static const Color liveRed = Color(0xFFE53935);
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
        // Tick diputar oleh window operator (lihat Sounds.playReveal /
        // startShuffleTicks) — bukan dari sub-window ini.
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
    // Layar pemenang imersif hanya bila hadiah punya foto yang valid.
    final immersive = _stage == _Stage.winner &&
        _gambar.isNotEmpty &&
        File(_gambar).existsSync();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          children: [
            if (immersive)
              _ImmersiveBackground(path: _gambar)
            else
              _BroadcastBackground(scale: s),
            // Partikel emas melayang hanya di idle (warisan tampilan
            // lama) — di atas background, di bawah semua panel.
            if (!immersive && _stage == _Stage.idle) const _Sparkles(),
            Positioned(
              top: 40 * s,
              left: 52 * s,
              right: 52 * s,
              child: _Header(scale: s, dark: immersive),
            ),
            Positioned(
              top: 36 * s,
              right: 44 * s,
              child: _LiveBadge(scale: s),
            ),
            Positioned(
              left: 52 * s,
              right: 52 * s,
              top: 208 * s,
              bottom: 52 * s,
              child: _bodyZone(s, immersive),
            ),
          ],
        ),
      ),
    );
  }

  /// Zona konten tiga kolom di bawah header.
  Widget _bodyZone(double s, bool immersive) {
    final prizePanel = _PrizePanel(scale: s, nama: _prize, gambar: _gambar);
    switch (_stage) {
      case _Stage.idle:
        return Row(
          children: [
            prizePanel,
            SizedBox(width: 36 * s),
            Expanded(
              child: _DrumShell(
                scale: s,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('UNDIAN HADIAH', style: _drumLabelStyle(s)),
                    SizedBox(height: 12 * s),
                    Icon(Icons.emoji_events, size: 150 * s, color: _Bc.gold),
                    SizedBox(height: 12 * s),
                    Text(
                      'SEGERA DIMULAI',
                      style: TextStyle(
                        fontSize: 40 * s,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 36 * s),
            _InfoPanel(
              scale: s,
              chipText: 'PENGUNDIAN HADIAH',
              numText: '— — — — — —',
              mode: _InfoMode.menunggu,
            ),
          ],
        );
      case _Stage.shuffle:
        return Row(
          children: [
            prizePanel,
            SizedBox(width: 36 * s),
            Expanded(
              child: _DrumShell(
                scale: s,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('NOMOR KUPON', style: _drumLabelStyle(s)),
                    SizedBox(height: 6 * s),
                    Text(_rolling, style: _drumNumberStyle(s)),
                  ],
                ),
              ),
            ),
            SizedBox(width: 36 * s),
            _InfoPanel(
              scale: s,
              chipText: 'SEDANG DIUNDI',
              numText: _rolling,
              mode: _InfoMode.menunggu,
            ),
          ],
        );
      case _Stage.winner:
        return _WinnerReveal(
          key: ValueKey('winner-$_coupon'),
          coupon: _coupon,
          nama: _nama,
          alamat: _alamat,
          hadiah: _hadiah,
          immersive: immersive,
          scale: s,
          prizePanel: prizePanel,
        );
      case _Stage.rejected:
        return Row(
          children: [
            prizePanel,
            SizedBox(width: 36 * s),
            Expanded(
              child: _CenterWarning(
                scale: s,
                title: 'KUPON SUDAH PERNAH MENANG',
                coupon: _coupon,
              ),
            ),
            SizedBox(width: 36 * s),
            _InfoPanel(
              scale: s,
              chipText: 'PENGUNDIAN HADIAH',
              numText: _coupon,
              mode: _InfoMode.rejected,
              nama: _nama,
              rejectedLine: _rejectedLine(),
            ),
          ],
        );
      case _Stage.notFound:
        return Row(
          children: [
            prizePanel,
            SizedBox(width: 36 * s),
            Expanded(
              child: _CenterWarning(
                scale: s,
                title: 'KUPON TIDAK TERDAFTAR',
                coupon: _coupon,
                extra: 'Mohon periksa kembali ke petugas',
              ),
            ),
            SizedBox(width: 36 * s),
            _InfoPanel(
              scale: s,
              chipText: 'PENGUNDIAN HADIAH',
              numText: _coupon,
              mode: _InfoMode.notFound,
            ),
          ],
        );
    }
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

/// Label kecil emas di atas angka drum.
TextStyle _drumLabelStyle(double s) => TextStyle(
      fontSize: 21 * s,
      fontWeight: FontWeight.bold,
      letterSpacing: 4 * s,
      color: _Bc.goldLight,
    );

/// Angka besar di dalam drum.
TextStyle _drumNumberStyle(double s) => TextStyle(
      fontSize: 82 * s,
      fontWeight: FontWeight.w900,
      letterSpacing: 3 * s,
      color: Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Background layar broadcast (v4): gradient navy 150° + glow radial
/// emas kanan-atas & kiri-bawah + gelombang emas sangat halus.
class _BroadcastBackground extends StatelessWidget {
  final double scale;
  const _BroadcastBackground({required this.scale});

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
        const Positioned.fill(child: CustomPaint(painter: _WavesPainter())),
      ],
    );
  }
}

/// Background layar pemenang imersif: foto hadiah memenuhi layar +
/// layer shade navy horizontal (transparan di kiri → pekat di kanan)
/// persis mockup gabungan.
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
  const _WavesPainter();

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
    canvas.drawPath(bottom, Paint()..color = const Color(0x1FD4AF37));

    final top = Path()
      ..moveTo(x(0), y(90))
      ..cubicTo(x(200), y(40), x(420), y(130), x(680), y(80))
      ..cubicTo(x(810), y(55), x(900), y(80), x(960), y(60))
      ..lineTo(x(960), y(0))
      ..lineTo(x(0), y(0))
      ..close();
    canvas.drawPath(top, Paint()..color = const Color(0x1AD4AF37));
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
/// Pada layar imersif teks brand berwarna GELAP (sisi kiri foto pada
/// mockup terang) dan judul diberi shadow — persis mockup gabungan.
class _Header extends StatelessWidget {
  final double scale;
  final bool dark;
  const _Header({required this.scale, required this.dark});

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
                color: dark ? const Color(0xFF0B3D91) : _Bc.goldLight,
              ),
            ),
            Text(
              'BANK BULUNGAN',
              style: TextStyle(
                fontSize: 48 * s,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5 * s,
                height: 1.05,
                color: dark ? const Color(0xFF072A63) : Colors.white,
              ),
            ),
            Text(
              'Mitra Terpercaya Membangun Masa Depan',
              style: TextStyle(
                fontSize: 23 * s,
                fontStyle: FontStyle.italic,
                color: dark ? const Color(0xFF31517F) : _Bc.tagline,
              ),
            ),
          ],
        ),
        const Spacer(),
        // Digeser kiri 148 untuk memberi ruang badge LIVE di pojok.
        Padding(
          padding: EdgeInsets.only(right: 148 * s),
          child: Column(
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
                  shadows: dark
                      ? [
                          Shadow(
                            color: const Color(0x66000000),
                            blurRadius: 10 * s,
                            offset: Offset(0, 2 * s),
                          ),
                        ]
                      : null,
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
        ),
      ],
    );
  }
}

/// Badge merah ● LIVE di pojok kanan atas.
class _LiveBadge extends StatelessWidget {
  final double scale;
  const _LiveBadge({required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        color: _Bc.liveRed,
        borderRadius: BorderRadius.circular(14 * s),
        boxShadow: [
          BoxShadow(
            color: const Color(0x80E53935),
            blurRadius: 24 * s,
            offset: Offset(0, 8 * s),
          ),
        ],
      ),
      child: Text(
        '● LIVE',
        style: TextStyle(
          fontSize: 25 * s,
          fontWeight: FontWeight.w800,
          letterSpacing: 1 * s,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Panel hadiah (kolom kiri): foto full-bleed di dalam bingkai emas,
/// pill label "HADIAH" menimpa batas foto, nama hadiah di bawahnya.
/// TANPA kartu putih tambahan — foto langsung memenuhi area panel,
/// jadi warna latar foto apa pun terlihat menyatu (sesuai mockup).
class _PrizePanel extends StatelessWidget {
  final double scale;
  final String nama;
  final String gambar;
  const _PrizePanel(
      {required this.scale, required this.nama, required this.gambar});

  bool get _hasPrize => nama.isNotEmpty;
  bool get _hasImage => gambar.isNotEmpty && File(gambar).existsSync();

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      width: 504 * s,
      decoration: BoxDecoration(
        color: _Bc.navyDeep,
        border: Border.all(color: _Bc.gold, width: 2 * s),
        borderRadius: BorderRadius.circular(28 * s),
        boxShadow: [
          BoxShadow(
            color: const Color(0x66000000),
            blurRadius: 60 * s,
            offset: Offset(0, 24 * s),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28 * s),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: _photoArea(s)),
                  // Pill label overlap -26 ke area foto.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: -26 * s,
                    child: Center(child: _pill(s)),
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  EdgeInsets.fromLTRB(28 * s, 42 * s, 28 * s, 28 * s),
              child: Text(
                _hasPrize ? nama : 'PENGUNDIAN HADIAH',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 33 * s,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoArea(double s) {
    if (_hasImage) {
      return Image.file(
        File(gambar),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderFoto(s),
      );
    }
    if (_hasPrize) return _placeholderFoto(s);
    // Belum ada hadiah dipilih: gradient navy + ikon piala emas.
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Bc.navy, _Bc.navyDeep],
        ),
      ),
      child: Center(
        child: Icon(Icons.emoji_events, size: 120 * s, color: _Bc.gold),
      ),
    );
  }

  /// Placeholder foto produk (gradient terang seperti mockup) untuk
  /// hadiah terpilih yang belum punya file gambar.
  Widget _placeholderFoto(double s) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F7FB), Color(0xFFD9E4F2)],
        ),
      ),
      child: Center(
        child: Icon(Icons.image, size: 120 * s, color: const Color(0xFF5B6B8C)),
      ),
    );
  }

  Widget _pill(double s) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 44 * s, vertical: 10 * s),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Bc.goldLight, _Bc.gold],
        ),
        borderRadius: BorderRadius.circular(14 * s),
        boxShadow: [
          BoxShadow(
            color: const Color(0x59000000),
            blurRadius: 20 * s,
            offset: Offset(0, 8 * s),
          ),
        ],
      ),
      child: Text(
        'HADIAH',
        style: TextStyle(
          fontSize: 29 * s,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5 * s,
          color: _Bc.onGold,
        ),
      ),
    );
  }
}

/// Drum mesin undi (kolom tengah): lingkaran kaca emas Ø476 +
/// pedestal emas + caption. Isi lingkaran tergantung stage.
class _DrumShell extends StatelessWidget {
  final double scale;
  final Widget child;
  const _DrumShell({required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              width: 476 * s,
              height: 476 * s,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border:
                    Border.all(color: const Color(0xBFD4AF37), width: 3 * s),
                gradient: const RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  colors: [
                    Color(0x38F3D27A),
                    Color(0x0DD4AF37),
                    Color(0x40000000),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x73000000),
                    blurRadius: 80 * s,
                    offset: Offset(0, 36 * s),
                  ),
                ],
              ),
              child: Center(child: child),
            ),
            // Pedestal emas, overlap -16 ke lingkaran.
            Positioned(
              bottom: -16 * s,
              child: Container(
                width: 340 * s,
                height: 32 * s,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_Bc.goldDark, _Bc.gold],
                  ),
                  borderRadius: BorderRadius.circular(12 * s),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 44 * s),
        Text(
          'MESIN PENGUNDI ELEKTRONIK',
          style: TextStyle(
            fontSize: 24 * s,
            fontWeight: FontWeight.bold,
            letterSpacing: 3 * s,
            color: _Bc.goldLight,
          ),
        ),
      ],
    );
  }
}

/// Panel peringatan amber di kolom tengah (kupon sudah pernah menang
/// / kupon tidak terdaftar). Tanpa confetti — ini validasi, bukan
/// perayaan.
class _CenterWarning extends StatelessWidget {
  final double scale;
  final String title;
  final String coupon;
  final String? extra;
  const _CenterWarning({
    required this.scale,
    required this.title,
    required this.coupon,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.warning_amber, size: 130 * s, color: _Bc.amber),
        SizedBox(height: 28 * s),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 54 * s,
            fontWeight: FontWeight.w900,
            color: _Bc.amberLight,
          ),
        ),
        SizedBox(height: 24 * s),
        Text(
          coupon,
          style: TextStyle(
            fontSize: 64 * s,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (extra != null) ...[
          SizedBox(height: 16 * s),
          Text(
            extra!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26 * s, color: _Bc.muted),
          ),
        ],
      ],
    );
  }
}

enum _InfoMode { menunggu, winner, rejected, notFound }

/// Panel info (kolom kanan): chip label, numbox emas, bar PEMENANG,
/// kotak pemenang, dan teks penutup di bawah. Dipakai semua stage;
/// pada layar imersif memakai varian kaca yang lebih pekat.
class _InfoPanel extends StatelessWidget {
  final double scale;
  final bool immersive;
  final String chipText;
  final String numText;
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
    required this.chipText,
    required this.numText,
    required this.mode,
    this.immersive = false,
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
      width: (immersive ? 544 : 524) * s,
      padding: EdgeInsets.all(28 * s),
      decoration: BoxDecoration(
        color: immersive ? const Color(0xC70A1633) : const Color(0xA810224D),
        border: Border.all(
          color: Color(immersive ? 0xBFD4AF37 : 0x99D4AF37),
          width: 1.5 * s,
        ),
        borderRadius: BorderRadius.circular(28 * s),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding:
                  EdgeInsets.symmetric(horizontal: 24 * s, vertical: 8 * s),
              decoration: BoxDecoration(
                color: AudienceTheme.navy700,
                border: Border.all(
                    color: const Color(0x80D4AF37), width: 1 * s),
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Text(
                chipText,
                style: TextStyle(
                  fontSize: 22 * s,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5 * s,
                  color: _Bc.goldLight,
                ),
              ),
            ),
          ),
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
                  'NOMOR KUPON PEMENANG',
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
                'Menunggu pengundian…',
                style: TextStyle(fontSize: 24 * s, color: _Bc.muted),
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
    return Text(
      'Nasabah Setia Bank Bulungan',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 24 * s,
        fontStyle: FontStyle.italic,
        color: _Bc.muted,
      ),
    );
  }
}

/// Partikel emas melayang untuk layar idle (dipertahankan dari
/// tampilan lama; digambar di atas background, di bawah panel).
class _Sparkles extends StatefulWidget {
  const _Sparkles();

  @override
  State<_Sparkles> createState() => _SparklesState();
}

class _SparklesState extends State<_Sparkles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Spark> _list;
  final _rand = Random(42);

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 11))
          ..repeat();
    _list = List.generate(70, (_) => _Spark.random(_rand));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: CustomPaint(painter: _SparksPainter(_ctrl, _list)),
    );
  }
}

/// Satu partikel cahaya emas.
class _Spark {
  double x0, phase, speed, size, driftAmp, swayFreq, alpha;
  Color color;

  _Spark.random(Random r)
      : x0 = r.nextDouble(),
        phase = r.nextDouble(),
        speed = 0.6 + r.nextDouble() * 1.4,
        size = 1.5 + r.nextDouble() * 3.5,
        driftAmp = 0.01 + r.nextDouble() * 0.03,
        swayFreq = 0.5 + r.nextDouble() * 1.5,
        alpha = 0.15 + r.nextDouble() * 0.45,
        color =
            r.nextBool() ? const Color(0xFFD4AF37) : const Color(0xFFFFF3C4);
}

class _SparksPainter extends CustomPainter {
  final AnimationController controller;
  final List<_Spark> sparks;

  _SparksPainter(this.controller, this.sparks) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final t = controller.value;
    final paint = Paint();
    for (final s in sparks) {
      final progress = (s.phase + t * s.speed) % 1.0;
      final y = size.height * (1.06 - progress * 1.16);
      final x = size.width * s.x0 +
          sin(t * 6.28318 * s.swayFreq + s.phase * 6.28318) *
              size.width *
              s.driftAmp;
      final a = (s.alpha * sin(progress * 3.14159)).clamp(0.0, 1.0);
      paint.color = s.color.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), s.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Scene pengumuman pemenang: nomor ng-roll ala mesin slot 2,6 detik
/// (easeOutQuart, 45 frame — pola yang sama seperti sebelumnya), lalu
/// mengunci + pop, kartu nama muncul, dan hujan confetti.
///
/// Varian non-imersif: panel hadiah | drum berisi nomor | panel info.
/// Varian imersif: blok nomor/nama/hadiah di kiri bawah menimpa foto
/// (nomor ikut ng-roll di numbox panel kanan + blok kiri), panel info
/// kaca pekat di kanan.
class _WinnerReveal extends StatefulWidget {
  final String coupon;
  final String nama;
  final String alamat;
  final String hadiah;
  final bool immersive;
  final double scale;
  final Widget prizePanel;

  const _WinnerReveal({
    super.key,
    required this.coupon,
    required this.nama,
    required this.alamat,
    required this.hadiah,
    required this.immersive,
    required this.scale,
    required this.prizePanel,
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
    // Catatan: tick slot TIDAK diputar dari window ini — window operator
    // memutarnya dengan pola yang sama (Sounds.playReveal: easeOutQuart
    // 2,6 dtk, 44 frame, lalu fanfare).
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
        double pop = 1.0;
        if (_locked) {
          final p = (_reveal.value / 0.12).clamp(0.0, 1.0);
          pop = 1.35 - 0.35 * Curves.easeOut.transform(p);
        }
        final info = _InfoPanel(
          scale: s,
          immersive: widget.immersive,
          chipText: 'PENGUNDIAN HADIAH',
          numText: display,
          mode: _InfoMode.winner,
          nama: widget.nama,
          alamat: widget.alamat,
          winnerReveal: _locked ? _nameCurve.value : 0,
          scriptReveal: _locked ? _scriptCurve.value : 0,
        );
        return Stack(
          children: [
            if (widget.immersive) ...[
              Positioned(
                left: 16 * s,
                bottom: 24 * s,
                child: _immersiveBlock(s, display),
              ),
              Positioned(right: 0, top: 0, bottom: 0, child: info),
            ] else
              Row(
                children: [
                  widget.prizePanel,
                  SizedBox(width: 36 * s),
                  Expanded(
                    child: _DrumShell(
                      scale: s,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('NOMOR KUPON', style: _drumLabelStyle(s)),
                          SizedBox(height: 6 * s),
                          Transform.scale(
                            scale: pop,
                            child: Text(display, style: _drumNumberStyle(s)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 36 * s),
                  info,
                ],
              ),
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

  /// Blok kiri-bawah layar imersif (mockup gabungan): pill PEMENANG,
  /// label nomor kupon, nama pemenang, nama hadiah — semua menimpa
  /// foto dengan shadow. Selama nomor masih ng-roll, yang tampil
  /// angka berjalannya; nama & hadiah muncul setelah mengunci.
  Widget _immersiveBlock(double s, String display) {
    final shadows = [
      Shadow(
        color: const Color(0x99000000),
        blurRadius: 14 * s,
        offset: Offset(0, 3 * s),
      ),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 900 * s),
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
