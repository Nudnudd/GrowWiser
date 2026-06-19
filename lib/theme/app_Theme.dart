import 'package:flutter/material.dart';

class AppColors {
  // Base
  static const Color black = Color(0xFF131610);
  static const Color darkBg = Color(0xFF1E1D1D);
  static const Color surface = Color(0xFF1A1A1A);

  //Main colors
  static const Color lightPink = Color(0xFFE5C5E1);
  static const Color blushPink = Color(0xFFF2A4D8);
  static const Color lightGreen = Color(0xFF717C3D);
  static const Color accentGreen = Color(0xFF405529);
  static const Color deepGreen = Color(0xFF0F2E15);
  static const Color seaGreen = Color(0xFF008748);

  // Cream / Tan
  static const Color cream = Color(0xFFD6B588);
  static const Color creamLight = Color(0xFFE9CBA3);
  static const Color creamCard = Color(0xFFB49B7A);

  // Card colors
  static const Color redBg = Color(0xFF7A070C);
  static const Color yellowWarning = Color(0xFFF9B700);
  static const Color tempCard = Color(0xFFC2441C);
  static const Color waterNext = Color(0xFFA8E63D);
   static const Color greenAccent = Color(0xFF139249);
  static const Color mutedGreen = Color(0xFF2ECC71);
  static const Color weatherBlue = Color(0xFF7692FF);
  static const Color blueLight = Color(0xFFADB2FA);
  static const Color blueDim = Color(0xFF3D518C);
  static const Color blueDark = Color(0xFF091420);

  // Text
  static const Color textPrimary = Color(0xFFE0E8E0);
  static const Color bgCard = Color(0xFFD2C9C9);
  static const Color textDim = Color(0xFF555555);
  static const Color white = Color(0xFFFFFFFF);
}

class AppTextStyles {
  static const String clashDisplay = 'ClashDisplay';
  static const String erode = 'Erode';
  static const String satoshi = 'Satoshi';

 

  static TextStyle headline(double size, Color color, {FontWeight weight = FontWeight.w400,double letterSpacing = 2}) =>
      TextStyle(fontFamily: satoshi, fontSize: size, color: color, letterSpacing: letterSpacing,fontWeight: weight,);

  static TextStyle mono(double size, Color color, {FontWeight weight = FontWeight.w400, double letterSpacing = 1}) =>
      TextStyle(fontFamily: clashDisplay, fontSize: size, color: color, fontWeight: weight, letterSpacing: letterSpacing);

  static TextStyle body(double size, Color color, {FontWeight weight = FontWeight.w400,double letterSpacing = 1}) =>
      TextStyle(fontFamily: erode, fontSize: size, color: color, fontWeight: weight,letterSpacing: letterSpacing);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.black,
        fontFamily: AppTextStyles.satoshi,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.deepGreen,
          surface: AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.black,
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: AppTextStyles.erode,
            fontSize: 20,
            color: AppColors.textPrimary,
            letterSpacing: 2,
          ),
        ),
      );
}