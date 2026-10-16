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

/// Design token untuk window OPERATOR: terang, bersih, profesional.
/// Navy sebagai warna primer, gold sebagai aksen — selaras dengan
/// identitas PT. BPR Bank Bulungan di layar penonton.
class OpTheme {
  static const navy = Color(0xFF10224D);
  static const navyDark = Color(0xFF0A1633);
  static const navySoft = Color(0xFFE8EDF7);
  static const gold = Color(0xFFD4AF37);
  static const goldDark = Color(0xFF9C7C1E);
  static const goldSoft = Color(0xFFFBF3DC);
  static const bg = Color(0xFFF3F5FA);
  static const cardBorder = Color(0xFFE2E8F2);
  static const textMuted = Color(0xFF5B6B8C);
  static const success = Color(0xFF15803D);
  static const successSoft = Color(0xFFE7F6EC);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFDECEC);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFEF3E2);

  /// Kartu putih standar: rounded, border halus, shadow lembut.
  static BoxDecoration card() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0D10224D), blurRadius: 18, offset: Offset(0, 6)),
        ],
      );

  /// Header kartu berwarna navy dengan teks putih.
  static BoxDecoration cardHeader() => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [navyDark, navy],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      );

  static TextStyle get tabTitle =>
      const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: navy);

  static TextStyle get tabSubtitle =>
      const TextStyle(fontSize: 13, color: textMuted, height: 1.5);

  static ButtonStyle get primaryButton => FilledButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      );

  static ButtonStyle get goldButton => FilledButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: navyDark,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      );

  static InputDecoration input(String label, {String? hint, Widget? prefix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: navy, width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
}
