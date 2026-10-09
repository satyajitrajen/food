import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Brand Warm Palette
  static const Color creamBg = Color(0xFFFBF9F4); // Warm ivory/cream background
  static const Color creamCard = Color(0xFFFFFFFF); // Clean white card surface
  static const Color creamSubtle = Color(0xFFF5EFE6); // Soft warm pill / highlight
  static const Color borderLight = Color(0xFFEBE3D5); // Gentle divider & border
  static const Color borderMedium = Color(0xFFD8CEBE); // Active input border

  // Accents — Hishobkr brand green. The logo green (#08A84C) is only 3.1:1
  // against white, below WCAG AA for button labels and text, so interactive
  // and text uses take the deeper shade; the logo shade stays decorative.
  static const Color brandGreen = Color(0xFF08A84C); // Logo / decorative only
  static const Color primaryGreen = Color(0xFF067A37); // 5.4:1 on white
  static const Color primaryGreenDark = Color(0xFF05652D); // Pressed state
  static const Color primaryGreenLight = Color(0xFFE6F6EC); // Light badge fill

  // Charcoal & Text — logo wordmark charcoal (#142029)
  static const Color textDark = Color(0xFF142029); // Deep slate-black
  static const Color textMuted = Color(0xFF6B655D); // Warm grey secondary
  static const Color textLight = Color(0xFF746E65); // Caption (4.8:1 on white)

  // Status & Indicators
  static const Color vegGreen = Color(0xFF237A35); // Basil green veg mark
  static const Color vegGreenBg = Color(0xFFEBFBEE);
  static const Color nonVegRed = Color(0xFFC92A2A); // Red non-veg mark
  static const Color nonVegRedBg = Color(0xFFFFF5F5);
  static const Color saffronAmber = Color(0xFF9A6200); // Pending / Dues (AA on its bg)
  static const Color saffronAmberBg = Color(0xFFFFF9DB);
  static const Color infoBlue = Color(0xFF1971C2);
  static const Color infoBlueBg = Color(0xFFE7F5FF);

  // Semantic states — use these for success/error/warning UI, not the
  // veg/non-veg food marks above.
  static const Color success = Color(0xFF237A35);
  static const Color successBg = Color(0xFFEBFBEE);
  static const Color danger = Color(0xFFC92A2A);
  static const Color dangerBg = Color(0xFFFFF5F5);
  static const Color warning = Color(0xFF9A6200);
  static const Color warningBg = Color(0xFFFFF9DB);
}

class AppTheme {
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.creamBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryGreen,
        primary: AppColors.primaryGreen,
        surface: AppColors.creamCard,
        surfaceContainer: AppColors.creamSubtle,
        onSurface: AppColors.textDark,
        outline: AppColors.borderLight,
      ),
      textTheme: baseTextTheme.copyWith(
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.creamCard,
        foregroundColor: AppColors.textDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          color: AppColors.textDark,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      chipTheme: ChipThemeData(
        selectedColor: AppColors.primaryGreenLight,
        checkmarkColor: AppColors.primaryGreen,
        side: const BorderSide(color: AppColors.borderLight),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      cardTheme: CardThemeData(
        color: AppColors.creamCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.borderLight, width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.creamCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.borderLight, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textDark,
          side: const BorderSide(color: AppColors.borderMedium, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.borderLight, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
        hintStyle: const TextStyle(color: AppColors.textLight, fontSize: 14),
      ),
    );
  }
}
