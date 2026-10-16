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
      await windowManager.setTitle('BPR Bank Bulungan - Layar Penonton');
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

  Widget _idleView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PENGUNDIAN HADIAH', style: AudienceTheme.title(84)),
          const SizedBox(height: 24),
          Text('acara undian berhadiah bank',
              style: AudienceTheme.subtitle(30)),
          if (_hadiah.isNotEmpty) ...[
            const SizedBox(height: 48),
            _prizeChip(_hadiah),
          ],
        ],
      );

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

  Widget _winnerView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('SELAMAT KEPADA', style: AudienceTheme.title(52)),
          Text('PEMENANG', style: AudienceTheme.title(96)),
          const SizedBox(height: 12),
          Text('pemenang undian berhadiah', style: AudienceTheme.subtitle(26)),
          const SizedBox(height: 56),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 88, vertical: 36),
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
                  _nama.toUpperCase(),
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
                  'Kupon $_coupon',
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
          const SizedBox(height: 40),
          _prizeChip(_hadiah),
        ],
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
