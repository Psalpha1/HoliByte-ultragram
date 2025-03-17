import 'package:flutter/material.dart';

final ThemeData darkTheme = ThemeData(
  useMaterial3: true, // Enables Material 3 for a modern look
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF006AFF),
    brightness: Brightness.dark, // Dark mode enabled
  ),
  scaffoldBackgroundColor:
      const Color(0xFF121212), // Darker background for better contrast

  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF1A1A1A),
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
    bodyLarge: TextStyle(fontSize: 16, color: Colors.white, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, color: Color(0xFFE0E0E0), height: 1.4),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.bold,
      color: Colors.white,
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
    fillColor: const Color(0xFF1E1E1E),
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
      borderSide: const BorderSide(color: Color(0xFF2C2C2C), width: 1),
    ),
    hintStyle: const TextStyle(color: Color(0xFF666666)),
    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
  ),

  cardTheme: CardTheme(
    color: const Color(0xFF1E1E1E),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFF2C2C2C), width: 1),
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
    color: Color(0xFF2C2C2C),
  ),

  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    minLeadingWidth: 0,
    horizontalTitleGap: 12,
    tileColor: Color(0xFF1E1E1E),
    textColor: Colors.white,
    iconColor: Color(0xFF006AFF),
  ),
);
