import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_view_model.dart';

/// Light/dark theme toggle, placed in the top-right of every auth screen's
/// app bar. Reads/writes the app-wide [ThemeViewModel].
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themeViewModel = context.watch<ThemeViewModel>();
    final isDark = themeViewModel.isDark(context);

    return IconButton(
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () => themeViewModel.toggleTheme(context),
    );
  }
}
