import 'package:flutter/material.dart';

class AppColors {

  // Light Theme
  static const Color primary = Color(0xFF0066CC);

  static const Color secondary =
  Color(0xFF00AEEF);

  static const Color background =
  Color(0xFFF5F7FA);

  static const Color card =
      Colors.white;

  static const Color textPrimary =
  Color(0xFF1A1A1A);

  static const Color textSecondary =
  Color(0xFF6E6E6E);

  // Dark Theme
  static const Color darkBackground =
  Color(0xFF121212);

  static const Color darkCard =
  Color(0xFF1E1E1E);

  static const Color darkText =
      Colors.white;

  static const Color darkTextSecondary = Color(0xFFA0A0A0);

  // Dashboard module accents (solid fills for icon squares on dark cards)
  static const Color moduleProjects = Color(0xFF2F6FED);
  static const Color moduleEmployees = Color(0xFF8B5CF6);
  static const Color moduleAttendance = Color(0xFF22A559);
  static const Color moduleNotifications = Color(0xFFF59E0B);
  static const Color moduleSettings = Color(0xFF1E3A5F);
  static const Color moduleTeamManagement = Color(0xFF6366F1);
  static const Color moduleTasks = Color(0xFFEC4899);
  static const Color moduleLeave = Color(0xFF14B8A6);
  static const Color moduleTimesheet = Color(0xFFD97706);
  static const Color moduleBilling = Color(0xFF0D9488);
  static const Color moduleStatusUpdate = Color(0xFF4F46E5);
  static const Color moduleReasonForDelay = Color(0xFFDC2626);
  static const Color moduleActivities = Color(0xFF7C3AED);
  static const Color moduleApproval = Color(0xFF0891B2);

  // Dashboard surfaces - the dark-mode look originally built for the
  // Captain Dashboard, now paired with a light-mode equivalent below via
  // the dashboardXxxFor(context) accessors instead of always being dark.
  static const Color dashboardBackground = Color(0xFF0B0B14);
  static const Color dashboardCard = Color(0xFF1A1A24);
  static const Color dashboardTextMuted = Color(0xFFAFAFC2);
  static const Color dashboardChevron = Color(0xFF6B6B80);

  static const Color dashboardGradientStart = Color(0xFF4B2AAD);
  static const Color dashboardGradientEnd = Color(0xFF1E3A8A);

  static const Color bottomNavActiveBackground = Color(0xFF6C4CE0);
  static const Color bottomNavInactive = Color(0xFF8A8A99);

  // Project status accents (completed reuses the primary brand color)
  static const Color statusActive = Color(0xFF2E7D32);
  static const Color statusCompleted = primary;
  static const Color statusOnHold = Color(0xFFB8860B);
  static const Color statusCancelled = Color(0xFFC62828);
  static const Color statusNotStarted = Color(0xFF6E6E6E);
  static const Color statusInactive = Color(0xFF9E9E9E);

  // Brightness-aware accessors - resolve a surface/text color against
  // whichever theme (light/dark) is currently active, instead of the
  // light-mode constant always being used regardless of ThemeMode.
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color backgroundFor(BuildContext context) =>
      isDark(context) ? darkBackground : background;

  static Color cardFor(BuildContext context) =>
      isDark(context) ? darkCard : card;

  static Color textPrimaryFor(BuildContext context) =>
      isDark(context) ? darkText : textPrimary;

  static Color textSecondaryFor(BuildContext context) =>
      isDark(context) ? darkTextSecondary : textSecondary;

  // Dashboard-specific accessors - dark mode keeps the original always-dark
  // "premium" palette; light mode falls back to the app's standard light
  // surface/text colors so the dashboard follows the theme toggle too.
  static Color dashboardBackgroundFor(BuildContext context) =>
      isDark(context) ? dashboardBackground : background;

  static Color dashboardSurfaceFor(BuildContext context) =>
      isDark(context) ? dashboardCard : card;

  static Color dashboardTextFor(BuildContext context) =>
      isDark(context) ? darkText : textPrimary;

  static Color dashboardTextMutedFor(BuildContext context) =>
      isDark(context) ? dashboardTextMuted : textSecondary;

  static Color dashboardChevronFor(BuildContext context) =>
      isDark(context) ? dashboardChevron : textSecondary;
}