import 'package:flutter/material.dart';

class AppColors {
  static const Color bg = Color(0xFF0A0F14);
  static const Color surface = Color(0xFF121A24);
  static const Color surface2 = Color(0xFF1A2431);
  static const Color line = Color(0x24FFFFFF);
  static const Color text = Color(0xFFEAF1F8);
  static const Color muted = Color(0xFF8CA1B6);
  static const Color accent = Color(0xFFFF7A2D);
  static const Color accent2 = Color(0xFFFFB06B);
  static const Color teal = Color(0xFF2DD4BF);
  static const Color red = Color(0xFFFF5A66);
  static const Color mapBg = Color(0xFF0D1420);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      secondary: AppColors.teal,
      surface: AppColors.surface,
      error: AppColors.red,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
      margin: EdgeInsets.zero,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: const TextStyle(color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
    ),
  );
}

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'RealRoute ',
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: AppColors.text,
        ),
        children: [
          TextSpan(
            text: 'RPG',
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
