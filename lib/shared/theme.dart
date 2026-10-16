import 'package:flutter/material.dart';

/// Tema navy-gold untuk layar penonton (selaras dengan overlay undian bank).
class AudienceTheme {
  static const navy900 = Color(0xFF0A1633);
  static const navy800 = Color(0xFF10224D);
  static const navy700 = Color(0xFF1A3268);
  static const gold = Color(0xFFD4AF37);
  static const goldLight = Color(0xFFF3D27A);
  static const goldDark = Color(0xFF9C7C1E);
  static const white = Colors.white;
  static const white70 = Colors.white70;

  static BoxDecoration background() => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [navy800, navy900, Color(0xFF060C1F)],
        ),
      );

  static TextStyle title(double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: size * 0.12,
        color: white,
        shadows: const [
          Shadow(
              color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 6)),
        ],
      );

  static TextStyle subtitle(double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w400,
        letterSpacing: size * 0.3,
        color: goldLight,
      );
}
