import 'dart:async';
import 'dart:math';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../shared/protocol.dart';
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

enum _Stage { idle, shuffle, winner }

class _AudienceAppState extends State<AudienceApp> {
  _Stage _stage = _Stage.idle;
  String _coupon = '';
  String _nama = '';
  String _hadiah = '';
  String _rolling = '000000';
  Timer? _rollTimer;
  final _rand = Random();

  static const _channel = WindowMethodChannel(
    AudienceProtocol.channelName,
    mode: ChannelMode.unidirectional,
  );

  @override
  void initState() {
    super.initState();
    _goFullscreen();
    _channel.setMethodCallHandler(_onMethod);
  }

  Future<void> _goFullscreen() async {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle('PT. BPR Bank Bulungan - Layar Penonton');
      await windowManager.setFullScreen(true);
    } catch (_) {
      // Plugin belum teregistrasi di sub-window (lihat README).
      // Window tetap jalan sebagai window biasa.
    }
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
        });
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
      }
    });
  }

  void _stopRoll() {
    _rollTimer?.cancel();
    _rollTimer = null;
  }

  @override
  void dispose() {
    _stopRoll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Container(
          decoration: AudienceTheme.background(),
          child: Stack(
            children: [
              const _GoldGlow(),
              Center(
                child: switch (_stage) {
                  _Stage.idle => _idleView(),
                  _Stage.shuffle => _shuffleView(),
                  _Stage.winner => _winnerView(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _idleView() => _AnimatedIdleView(hadiah: _hadiah);

  Widget _shuffleView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('MENGUNDI', style: AudienceTheme.title(64)),
          const SizedBox(height: 16),
          if (_hadiah.isNotEmpty) _prizeChip(_hadiah),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 32),
            decoration: BoxDecoration(
              border: Border.all(color: AudienceTheme.gold, width: 3),
              borderRadius: BorderRadius.circular(24),
              color: const Color(0x22000000),
            ),
            child: Text(
              _rolling,
              style: const TextStyle(
                fontSize: 120,
                fontWeight: FontWeight.w900,
                letterSpacing: 16,
                color: AudienceTheme.goldLight,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );

  Widget _winnerView() => _AnimatedWinnerView(
        key: ValueKey('winner-$_coupon'),
        nama: _nama,
        coupon: _coupon,
        hadiah: _hadiah,
      );

  Widget _prizeChip(String hadiah) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AudienceTheme.gold, width: 2),
          borderRadius: BorderRadius.circular(999),
          color: const Color(0x22D4AF37),
        ),
        child: Text(
          hadiah,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            color: AudienceTheme.goldLight,
            letterSpacing: 2,
          ),
        ),
      );
}

/// Dekorasi cahaya emas sederhana di latar.
class _GoldGlow extends StatelessWidget {
  const _GoldGlow();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: -120,
          left: -80,
          child: _Blur(color: Color(0x44D4AF37), size: 420),
        ),
        Positioned(
          bottom: -140,
          right: -60,
          child: _Blur(color: Color(0x332A4A8F), size: 480),
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
  const _AnimatedIdleView({required this.hadiah});

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
    return Stack(
      children: [
        // Glow berdenyut.
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final s = 1.0 + _pulse.value * 0.18;
            return Transform.scale(scale: s, child: child);
          },
          child: const _GoldGlow(),
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
              const Text(
                'PT. BPR BANK BULUNGAN',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 12,
                  color: AudienceTheme.goldLight,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: 220,
                height: 2,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Color(0x00000000),
                    AudienceTheme.gold,
                    Color(0x00000000),
                  ]),
                ),
              ),
              const SizedBox(height: 32),
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
                child:
                    Text('PENGUNDIAN HADIAH', style: AudienceTheme.title(84)),
              ),
              const SizedBox(height: 24),
              // "SEGERA DIMULAI" + titik animasi.
              AnimatedBuilder(
                animation: _dots,
                builder: (context, _) {
                  final n = 1 + (_dots.value * 2.999).floor();
                  return Text('SEGERA DIMULAI${'.' * n}',
                      style: AudienceTheme.subtitle(30));
                },
              ),
              if (widget.hadiah.isNotEmpty) ...[
                const SizedBox(height: 48),
                _FloatingPrizeChip(hadiah: widget.hadiah),
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
  const _FloatingPrizeChip({required this.hadiah});

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
        offset: Offset(0, -8 * _float.value),
        child: _PrizeChipStatic(hadiah: widget.hadiah),
      ),
    );
  }
}

class _PrizeChipStatic extends StatelessWidget {
  final String hadiah;
  const _PrizeChipStatic({required this.hadiah});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(color: AudienceTheme.gold, width: 2),
        borderRadius: BorderRadius.circular(999),
        color: const Color(0x22D4AF37),
      ),
      child: Text(
        hadiah,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          color: AudienceTheme.goldLight,
          letterSpacing: 2,
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
  const _AnimatedWinnerView(
      {super.key,
      required this.nama,
      required this.coupon,
      required this.hadiah});

  @override
  State<_AnimatedWinnerView> createState() => _AnimatedWinnerViewState();
}

class _AnimatedWinnerViewState extends State<_AnimatedWinnerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Confetti> _pieces;
  final _rand = Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 4500))
      ..forward();
    _pieces = List.generate(90, (_) => _Confetti.random(_rand));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ConfettiPainter(_controller, _pieces),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: CurvedAnimation(
                    parent: _controller, curve: const Interval(0.0, 0.25)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SELAMAT KEPADA', style: AudienceTheme.title(52)),
                    Text('PEMENANG', style: AudienceTheme.title(96)),
                    const SizedBox(height: 12),
                    Text('PT. BPR Bank Bulungan',
                        style: AudienceTheme.subtitle(26)),
                  ],
                ),
              ),
              const SizedBox(height: 56),
              ScaleTransition(
                scale: Tween<double>(begin: 0.6, end: 1.0).animate(entrance),
                child: FadeTransition(
                  opacity: CurvedAnimation(
                      parent: _controller, curve: const Interval(0.1, 0.35)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 88, vertical: 36),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AudienceTheme.goldDark,
                          AudienceTheme.gold,
                          AudienceTheme.goldDark
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 32,
                            offset: Offset(0, 12)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.nama.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w800,
                            color: AudienceTheme.navy900,
                            letterSpacing: 4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Kupon ${widget.coupon}',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            color: AudienceTheme.navy800,
                            letterSpacing: 6,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              if (widget.hadiah.isNotEmpty)
                FadeTransition(
                  opacity: CurvedAnimation(
                      parent: _controller, curve: const Interval(0.35, 0.55)),
                  child: _PrizeChipStatic(hadiah: widget.hadiah),
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
