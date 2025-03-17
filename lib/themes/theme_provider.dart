import 'package:flutter/material.dart';
import 'package:we_chat/themes/light_mode.dart';
import 'package:we_chat/themes/dark_mode.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  static const String _themeKey = 'theme_mode';
  static const String _useSystemThemeKey = 'use_system_theme';
  static const Duration animationDuration = Duration(milliseconds: 300);

  bool _isDarkMode =
      SchedulerBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
  bool _useSystemTheme = true;
  ThemeData _themeData =
      SchedulerBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark
          ? darkTheme
          : lightTheme;

  // Animation controllers
  double _themeAnimationProgress = 0.0;
  bool _isAnimating = false;

  ThemeData get themeData => _themeData;
  bool get isDarkMode => _isDarkMode;
  bool get useSystemTheme => _useSystemTheme;
  Duration get duration => animationDuration;
  double get themeAnimationProgress => _themeAnimationProgress;
  bool get isAnimating => _isAnimating;

  ThemeProvider() {
    _initializeTheme();
  }

  Future<void> _initializeTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _useSystemTheme = prefs.getBool(_useSystemThemeKey) ?? true;
    _isDarkMode = prefs.getBool(_themeKey) ?? _getSystemThemeMode();
    _themeAnimationProgress = _isDarkMode ? 1.0 : 0.0;

    if (_useSystemTheme) {
      _isDarkMode = _getSystemThemeMode();
      _themeData = _isDarkMode ? darkTheme : lightTheme;

      SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
          () {
        if (_useSystemTheme) {
          _updateThemeBasedOnSystem();
        }
      };
    } else {
      _themeData = _isDarkMode ? darkTheme : lightTheme;
    }

    notifyListeners();
  }

  bool _getSystemThemeMode() {
    return SchedulerBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  void _updateThemeBasedOnSystem() {
    final isDark = _getSystemThemeMode();
    if (_isDarkMode != isDark) {
      _isDarkMode = isDark;
      _themeAnimationProgress = isDark ? 1.0 : 0.0;
      _themeData = isDark ? darkTheme : lightTheme;
      notifyListeners();
    }
  }

  Future<void> toggleTheme() async {
    if (_isAnimating) return;
    _isAnimating = true;
    _isDarkMode = !_isDarkMode;
    notifyListeners();

    // Animate theme change
    const steps = 60; // 60 fps for 300ms = ~18 frames
    final stepDuration = (animationDuration.inMilliseconds ~/ steps);
    final isGoingDark = _isDarkMode;

    for (var i = 1; i <= steps; i++) {
      await Future.delayed(Duration(milliseconds: stepDuration));
      _themeAnimationProgress = isGoingDark ? i / steps : 1 - (i / steps);
      notifyListeners();
    }

    _themeData = _isDarkMode ? darkTheme : lightTheme;
    _useSystemTheme = false;
    _isAnimating = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, _isDarkMode);
    await prefs.setBool(_useSystemThemeKey, false);

    notifyListeners();
  }

  Future<void> setUseSystemTheme(bool value) async {
    _useSystemTheme = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useSystemThemeKey, value);

    if (value) {
      _updateThemeBasedOnSystem();
    }
  }
}
