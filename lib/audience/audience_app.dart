import 'dart:async';
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

class _AudienceAppState extends State<AudienceApp> with WindowListener {
  _Stage _stage = _Stage.idle;
  String _coupon = '';
  String _nama = '';
  String _hadiah = '';
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
          final prize = (call.arguments as Map?)?[AudienceProtocol.argHadiah];
          if (prize is String && prize.isNotEmpty) _hadiah = prize;
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
          _hadiah = (args[AudienceProtocol.argHadiah] ?? '').toString();
          _stage = _Stage.winner;
        });
        break;
      case AudienceProtocol.showPrize:
        final args = (call.arguments as Map?) ?? {};
        setState(() {
          _hadiah = (args[AudienceProtocol.argHadiah] ?? '').toString();
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Container(
          decoration: AudienceTheme.background(),
          child: Stack(
            children: [
              _GoldGlow(scale: s),
              Center(
                child: switch (_stage) {
                  _Stage.idle => _idleView(s),
                  _Stage.shuffle => _shuffleView(s),
                  _Stage.winner => _winnerView(s),
                  _Stage.rejected => _rejectedView(s),
                  _Stage.notFound => _notFoundView(s),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _idleView(double s) => _AnimatedIdleView(hadiah: _hadiah, scale: s);

  Widget _shuffleView(double s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('MENGUNDI', style: AudienceTheme.title(64 * s)),
          SizedBox(height: 16 * s),
          if (_hadiah.isNotEmpty) _prizeChip(s, _hadiah),
          SizedBox(height: 48 * s),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 72 * s, vertical: 32 * s),
            decoration: BoxDecoration(
              border: Border.all(color: AudienceTheme.gold, width: 3),
              borderRadius: BorderRadius.circular(24 * s),
              color: const Color(0x22000000),
            ),
            child: Text(
              _rolling,
              style: TextStyle(
                fontSize: 120 * s,
                fontWeight: FontWeight.w900,
                letterSpacing: 16 * s,
                color: AudienceTheme.goldLight,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );

  Widget _winnerView(double s) => _AnimatedWinnerView(
        key: ValueKey('winner-$_coupon'),
        nama: _nama,
        coupon: _coupon,
        hadiah: _hadiah,
        scale: s,
      );

  /// Tampilan penolakan: kupon sudah pernah menang.
  /// Gaya peringatan (amber) — beda dari perayaan pemenang (emas),
  /// tanpa fanfare & tanpa confetti.
  Widget _rejectedView(double s) {
    const amber = Color(0xFFF59E0B);
    const amberLight = Color(0xFFFCD34D);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 110 * s,
          height: 110 * s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: amber, width: 4),
            color: const Color(0x22F59E0B),
          ),
          child: Icon(Icons.block, size: 60 * s, color: amber),
        ),
        SizedBox(height: 28 * s),
        Text(
          'KUPON SUDAH MENANG',
          style: AudienceTheme.title(56 * s).copyWith(color: amberLight),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 24 * s),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 56 * s, vertical: 20 * s),
          decoration: BoxDecoration(
            border: Border.all(color: amber, width: 3),
            borderRadius: BorderRadius.circular(20 * s),
            color: const Color(0x22000000),
          ),
          child: Text(
            _coupon,
            style: TextStyle(
              fontSize: 84 * s,
              fontWeight: FontWeight.w900,
              letterSpacing: 12 * s,
              color: amberLight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(height: 24 * s),
        Text(
          _nama,
          style: TextStyle(
            fontSize: 44 * s,
            fontWeight: FontWeight.w700,
            color: AudienceTheme.white,
            letterSpacing: 2 * s,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8 * s),
        if (_rejectedRekening.isNotEmpty)
          Text(
            'Rek. $_rejectedRekening',
            style: TextStyle(fontSize: 26 * s, color: AudienceTheme.white70),
            textAlign: TextAlign.center,
          ),
        if (_hadiah.isNotEmpty)
          Text(
            'Sebelumnya memenangkan "$_hadiah"',
            style: TextStyle(fontSize: 30 * s, color: AudienceTheme.white70),
            textAlign: TextAlign.center,
          ),
        if (_rejectedWaktu.isNotEmpty)
          Text(
            'pada $_rejectedWaktu',
            style: TextStyle(fontSize: 26 * s, color: AudienceTheme.white70),
            textAlign: TextAlign.center,
          ),
        SizedBox(height: 32 * s),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 40 * s, vertical: 14 * s),
          decoration: BoxDecoration(
            border: Border.all(color: amber, width: 2),
            borderRadius: BorderRadius.circular(999),
            color: const Color(0x22F59E0B),
          ),
          child: Text(
            'SILAKAN UNDI ULANG',
            style: TextStyle(
              fontSize: 30 * s,
              fontWeight: FontWeight.w700,
              color: amberLight,
              letterSpacing: 3 * s,
            ),
          ),
        ),
      ],
    );
  }

  /// Tampilan validasi: kupon tidak terdaftar di database.
  /// Dipakai di undi manual — nomor keluar di depan penonton, operator
  /// wajib menyampaikan valid/tidaknya. Gaya peringatan (amber),
  /// tanpa fanfare & tanpa confetti.
  Widget _notFoundView(double s) {
    const amber = Color(0xFFF59E0B);
    const amberLight = Color(0xFFFCD34D);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 110 * s,
          height: 110 * s,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: amber, width: 4),
            color: const Color(0x22F59E0B),
          ),
          child: Icon(Icons.search_off, size: 60 * s, color: amber),
        ),
        SizedBox(height: 28 * s),
        Text(
          'KUPON TIDAK TERDAFTAR',
          style: AudienceTheme.title(56 * s).copyWith(color: amberLight),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 24 * s),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 56 * s, vertical: 20 * s),
          decoration: BoxDecoration(
            border: Border.all(color: amber, width: 3),
            borderRadius: BorderRadius.circular(20 * s),
            color: const Color(0x22000000),
          ),
          child: Text(
            _coupon,
            style: TextStyle(
              fontSize: 84 * s,
              fontWeight: FontWeight.w900,
              letterSpacing: 12 * s,
              color: amberLight,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(height: 32 * s),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 40 * s, vertical: 14 * s),
          decoration: BoxDecoration(
            border: Border.all(color: amber, width: 2),
            borderRadius: BorderRadius.circular(999),
            color: const Color(0x22F59E0B),
          ),
          child: Text(
            'MOHON PERIKSA KEMBALI NOMOR KUPON',
            style: TextStyle(
              fontSize: 28 * s,
              fontWeight: FontWeight.w700,
              color: amberLight,
              letterSpacing: 2 * s,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _prizeChip(double s, String hadiah) => Container(
        padding: EdgeInsets.symmetric(horizontal: 40 * s, vertical: 16 * s),
        decoration: BoxDecoration(
          border: Border.all(color: AudienceTheme.gold, width: 2),
          borderRadius: BorderRadius.circular(999),
          color: const Color(0x22D4AF37),
        ),
        child: Text(
          hadiah,
          style: TextStyle(
            fontSize: 32 * s,
            fontWeight: FontWeight.w600,
            color: AudienceTheme.goldLight,
            letterSpacing: 2 * s,
          ),
        ),
      );
}

/// Dekorasi cahaya emas sederhana di latar.
class _GoldGlow extends StatelessWidget {
  final double scale;
  const _GoldGlow({this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -120 * scale,
          left: -80 * scale,
          child: _Blur(color: const Color(0x44D4AF37), size: 420 * scale),
        ),
        Positioned(
          bottom: -140 * scale,
          right: -60 * scale,
          child: _Blur(color: const Color(0x332A4A8F), size: 480 * scale),
        ),
      ],
    );
  }
}

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

/// Layar idle animasi: partikel emas melayang, judul shimmer, glow berdenyut.
class _AnimatedIdleView extends StatefulWidget {
  final String hadiah;
  final double scale;
  const _AnimatedIdleView({required this.hadiah, this.scale = 1.0});

  @override
  State<_AnimatedIdleView> createState() => _AnimatedIdleViewState();
}

class _AnimatedIdleViewState extends State<_AnimatedIdleView>
    with TickerProviderStateMixin {
  late final AnimationController _shimmer;
  late final AnimationController _pulse;
  late final AnimationController _sparks;
  late final AnimationController _dots;
  late final List<_Spark> _sparkList;
  final _rand = Random(42);

  @override
  void initState() {
    super.initState();
    _shimmer =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat(reverse: true);
    _sparks =
        AnimationController(vsync: this, duration: const Duration(seconds: 11))
          ..repeat();
    _dots = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _sparkList = List.generate(70, (_) => _Spark.random(_rand));
  }

  @override
  void dispose() {
    _shimmer.dispose();
    _pulse.dispose();
    _sparks.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return Stack(
      children: [
        // Glow berdenyut.
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final sc = 1.0 + _pulse.value * 0.18;
            return Transform.scale(scale: sc, child: child);
          },
          child: _GoldGlow(scale: s),
        ),
        // Partikel emas melayang.
        Positioned.fill(
          child: CustomPaint(
            painter: _SparksPainter(_sparks, _sparkList),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'PT. BPR BANK BULUNGAN',
                style: TextStyle(
                  fontSize: 30 * s,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 12 * s,
                  color: AudienceTheme.goldLight,
                ),
              ),
              SizedBox(height: 16 * s),
              Container(
                width: 220 * s,
                height: 2,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color(0x00000000),
                    AudienceTheme.gold,
                    Color(0x00000000),
                  ]),
                ),
              ),
              SizedBox(height: 32 * s),
              // Judul dengan efek shimmer emas.
              AnimatedBuilder(
                animation: _shimmer,
                builder: (context, child) {
                  final p = _shimmer.value;
                  return ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => LinearGradient(
                      colors: const [
                        AudienceTheme.gold,
                        Color(0xFFFFF3C4),
                        AudienceTheme.gold,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                      begin: Alignment(-2.6 + 3.2 * p, 0),
                      end: Alignment(-0.6 + 3.2 * p, 0),
                    ).createShader(bounds),
                    child: child,
                  );
                },
                child: Text('PENGUNDIAN HADIAH',
                    style: AudienceTheme.title(84 * s)),
              ),
              SizedBox(height: 24 * s),
              // "SEGERA DIMULAI" + titik animasi.
              AnimatedBuilder(
                animation: _dots,
                builder: (context, _) {
                  final n = 1 + (_dots.value * 2.999).floor();
                  return Text('SEGERA DIMULAI${'.' * n}',
                      style: AudienceTheme.subtitle(30 * s));
                },
              ),
              if (widget.hadiah.isNotEmpty) ...[
                SizedBox(height: 48 * s),
                _FloatingPrizeChip(hadiah: widget.hadiah, scale: s),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Chip hadiah yang mengambang lembut.
class _FloatingPrizeChip extends StatefulWidget {
  final String hadiah;
  final double scale;
  const _FloatingPrizeChip({required this.hadiah, this.scale = 1.0});

  @override
  State<_FloatingPrizeChip> createState() => _FloatingPrizeChipState();
}

class _FloatingPrizeChipState extends State<_FloatingPrizeChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float;

  @override
  void initState() {
    super.initState();
    _float =
        AnimationController(vsync: this, duration: const Duration(seconds: 3))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _float,
      builder: (context, _) => Transform.translate(
        offset: Offset(0, -8 * widget.scale * _float.value),
        child: _PrizeChipStatic(hadiah: widget.hadiah, scale: widget.scale),
      ),
    );
  }
}

class _PrizeChipStatic extends StatelessWidget {
  final String hadiah;
  final double scale;
  const _PrizeChipStatic({required this.hadiah, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 40 * s, vertical: 16 * s),
      decoration: BoxDecoration(
        border: Border.all(color: AudienceTheme.gold, width: 2),
        borderRadius: BorderRadius.circular(999),
        color: const Color(0x22D4AF37),
      ),
      child: Text(
        hadiah,
        style: TextStyle(
          fontSize: 32 * s,
          fontWeight: FontWeight.w600,
          color: AudienceTheme.goldLight,
          letterSpacing: 2 * s,
        ),
      ),
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

/// Layar pemenang animasi: kartu scale-in + hujan confetti emas.
class _AnimatedWinnerView extends StatefulWidget {
  final String nama;
  final String coupon;
  final String hadiah;
  final double scale;
  const _AnimatedWinnerView(
      {super.key,
      required this.nama,
      required this.coupon,
      required this.hadiah,
      this.scale = 1.0});

  @override
  State<_AnimatedWinnerView> createState() => _AnimatedWinnerViewState();
}

class _AnimatedWinnerViewState extends State<_AnimatedWinnerView>
    with TickerProviderStateMixin {
  late final AnimationController _roll; // slot-machine nomor (2.6 dtk)
  late final CurvedAnimation _rollCurve; // easeOut = melambat di akhir
  late final AnimationController _reveal; // kartu nama + confetti
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
    _roll.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
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
    final entrance = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ConfettiPainter(_reveal, _pieces),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: CurvedAnimation(
                    parent: _roll, curve: const Interval(0.0, 0.25)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SELAMAT KEPADA', style: AudienceTheme.title(52 * s)),
                    Text('PEMENANG', style: AudienceTheme.title(96 * s)),
                    SizedBox(height: 12 * s),
                    Text('PT. BPR Bank Bulungan',
                        style: AudienceTheme.subtitle(26 * s)),
                  ],
                ),
              ),
              SizedBox(height: 44 * s),
              // Kotak nomor: ng-roll seperti mesin slot, lalu mengunci.
              AnimatedBuilder(
                animation: Listenable.merge([_roll, _reveal]),
                builder: (context, _) {
                  final tick = (_rollCurve.value * 45).floor();
                  final text = _locked ? widget.coupon : _rollNumber(tick);
                  double scale = 1.0;
                  if (_locked) {
                    final p = (_reveal.value / 0.12).clamp(0.0, 1.0);
                    scale = 1.35 - 0.35 * Curves.easeOut.transform(p);
                  }
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 64 * s, vertical: 28 * s),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AudienceTheme.goldDark,
                            AudienceTheme.gold,
                            AudienceTheme.goldDark
                          ],
                        ),
                        borderRadius: BorderRadius.circular(24 * s),
                        boxShadow: const [
                          BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 40,
                              offset: Offset(0, 14)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'NOMOR KUPON',
                            style: TextStyle(
                              fontSize: 20 * s,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 10 * s,
                              color: AudienceTheme.navy800,
                            ),
                          ),
                          SizedBox(height: 8 * s),
                          Text(
                            text,
                            style: TextStyle(
                              fontSize: 108 * s,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 14 * s,
                              color: AudienceTheme.navy900,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 36 * s),
              // Kartu nama muncul setelah nomor mengunci (layout tetap
              // di-reserve agar tidak ada lompatan).
              ScaleTransition(
                scale: Tween<double>(begin: 0.6, end: 1.0).animate(entrance),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                      parent: _reveal, curve: const Interval(0.1, 0.35)),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 72 * s, vertical: 26 * s),
                    decoration: BoxDecoration(
                      border: Border.all(color: AudienceTheme.gold, width: 2),
                      borderRadius: BorderRadius.circular(20 * s),
                      color: const Color(0x22000000),
                    ),
                    child: Text(
                      widget.nama.toUpperCase(),
                      style: TextStyle(
                        fontSize: 56 * s,
                        fontWeight: FontWeight.w800,
                        color: AudienceTheme.goldLight,
                        letterSpacing: 4 * s,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 32 * s),
              if (widget.hadiah.isNotEmpty)
                FadeTransition(
                  opacity: CurvedAnimation(
                      parent: _reveal, curve: const Interval(0.35, 0.55)),
                  child: _PrizeChipStatic(hadiah: widget.hadiah, scale: s),
                ),
            ],
          ),
        ),
      ],
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
