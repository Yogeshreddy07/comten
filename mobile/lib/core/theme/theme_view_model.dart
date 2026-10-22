import 'package:flutter/material.dart';

import '../utils/preference_util.dart';

/// Manages the user's light/dark theme choice, persisted across app
/// restarts. Defaults to following the system setting until the user
/// explicitly toggles it via [ThemeToggleButton].
class ThemeViewModel extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeViewModel() {
    final saved = PreferenceUtil.getThemeMode();
    if (saved != null) {
      _themeMode = saved;
    }
  }

  ThemeMode get themeMode => _themeMode;

  bool isDark(BuildContext context) {
    if (_themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    }
    return _themeMode == ThemeMode.dark;
  }

  Future<void> toggleTheme(BuildContext context) async {
    final currentlyDark = isDark(context);
    _themeMode = currentlyDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    await PreferenceUtil.setThemeMode(_themeMode);
  }
}
