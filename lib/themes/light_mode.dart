import 'package:flutter/material.dart';

final ThemeData lightTheme = ThemeData(
  useMaterial3: true, // Enables Material 3 for a modern look
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF006AFF),
    brightness: Brightness.light, // Adapts to system theme
  ),
  scaffoldBackgroundColor: const Color(0xFFF8F9FA),

  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF006AFF),
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),

  textTheme: const TextTheme(
    bodyLarge: TextStyle(
      fontSize: 16,
      color: Color(0xFF2C2C2C),
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      color: Color(0xFF4A4A4A),
      height: 1.4,
    ),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: Color(0xFF1A1A1A),
      letterSpacing: -0.5,
    ),
  ),

  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      backgroundColor: const Color(0xFF006AFF),
      foregroundColor: Colors.white,
    ),
  ),

  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF006AFF), width: 2),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
    ),
    hintStyle: const TextStyle(color: Color(0xFF9E9E9E)),
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  ),

  cardTheme: CardTheme(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFE0E0E0), width: 1),
    ),
  ),

  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  ),

  iconTheme: const IconThemeData(
    color: Color(0xFF006AFF),
    size: 24,
  ),

  buttonTheme: const ButtonThemeData(
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12))),
    buttonColor: Color(0xFF006AFF),
    textTheme: ButtonTextTheme.primary,
  ),

  dividerTheme: const DividerThemeData(
    space: 1,
    thickness: 1,
    color: Color(0xFFE0E0E0),
  ),

  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    minLeadingWidth: 0,
    horizontalTitleGap: 12,
    tileColor: Colors.white,
    textColor: Color(0xFF2C2C2C),
    iconColor: Color(0xFF006AFF),
  ),
);
