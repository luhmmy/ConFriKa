import 'package:flutter/material.dart';

/// Brand colors and typography derived from the ConFriKa Product Concept & Identity.
class ConFriKaColors {
  static const Color oceanBlue = Color(0xFF154C79);
  static const Color sunsetOrange = Color(0xFFE87722);
  static const Color savannaGreen = Color(0xFF2D8A4E);
  static const Color deepSlate = Color(0xFF0F172A);
  static const Color cardSurface = Color(0xFF1E293B);
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color amberHighlight = Color(0xFFF59E0B);
}

class ConFriKaTheme {
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ConFriKaColors.oceanBlue,
      primary: ConFriKaColors.oceanBlue,
      secondary: ConFriKaColors.sunsetOrange,
      tertiary: ConFriKaColors.savannaGreen,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ConFriKaColors.lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: ConFriKaColors.deepSlate,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: ConFriKaColors.deepSlate.withValues(alpha: 0.15)),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: ConFriKaColors.oceanBlue,
      primary: const Color(0xFF38BDF8),
      secondary: ConFriKaColors.sunsetOrange,
      tertiary: const Color(0xFF34D399),
      surface: ConFriKaColors.cardSurface,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ConFriKaColors.deepSlate,
      cardTheme: CardThemeData(
        elevation: 0,
        color: ConFriKaColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    );
  }
}
