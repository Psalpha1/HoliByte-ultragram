import 'package:flutter/material.dart';

/// UI Constants used throughout the app
class AppConstants {
  // Search bar constants
  static const double searchBarPadding = 16.0;
  static const double borderRadius = 20.0;
  static const Duration animationDuration = Duration(milliseconds: 300);
  
  // Refresh indicator constants
  static const double refreshTriggerPullDistance = 100.0;
  static const double refreshIndicatorSize = 40.0;
  
  // App bar constants
  static const double appBarHeight = 80.0;
  static const double appBarIconSize = 40.0;
  static const EdgeInsetsGeometry appBarPadding = EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
  static const TextStyle appBarTitleStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  
  // Gradient color constants
  static const List<Color> homeGradient = [
    Color(0xFF2196F3), // blue
    Color(0xFF9C27B0), // purple
    Color(0xFFE91E63), // pink
  ];
  
  static const List<Color> groupGradient = [
    Color(0xFF9C27B0), // purple
    Color(0xFFE91E63), // pink
    Color(0xFFFF9800), // orange
  ];
  
  static const List<Color> aiGradient = [
    Color(0xFF00BCD4), // cyan
    Color(0xFF3F51B5), // indigo
    Color(0xFF9C27B0), // purple
  ];
  
  // Page transition duration
  static const Duration pageTransitionDuration = Duration(milliseconds: 300);
  
  // Hero tag constants
  static const String homeHeroTag = 'home_profile';
  static const String groupHeroTag = 'group_profile';
  static const String chatCardHeroTag = 'chat_card';
  static const String searchUserHeroTag = 'search_user';
  static const String viewProfileHeroTag = 'view_profile';
  
  // FAB hero tag constants
  static const String homeFabHeroTag = 'home_fab';
  static const String groupFabHeroTag = 'group_fab';
  
  // Prevent instantiation
  AppConstants._();
} 