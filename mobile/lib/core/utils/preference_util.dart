import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_token_store.dart';

class PreferenceUtil {
  static SharedPreferences? _prefs;
  static AuthTokenStore? _tokens;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    _tokens ??= AuthTokenStore(_prefs!);
    await _tokens!.migrateLegacy();
  }

  static const String _keyLastEmployeeCode = 'last_employee_code';
  static const String _keyJwtPrefix = 'jwt_token_';
  static const String _keyFcmTokenPrefix = 'fcm_token_';
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyWalkthroughSeenPrefix = 'walkthrough_seen_';

  // Theme mode (light/dark). Returns null if the user hasn't chosen one yet,
  // so callers can fall back to following the system setting.
  static Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setString(_keyThemeMode, mode.name);
  }

  static ThemeMode? getThemeMode() {
    switch (_prefs?.getString(_keyThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }

  // Last active employee code
  static Future<void> setLastEmployeeCode(String code) async {
    await _prefs?.setString(_keyLastEmployeeCode, code);
  }

  static String? getLastEmployeeCode() {
    return _prefs?.getString(_keyLastEmployeeCode);
  }

  // JWT Token for API requests
  static Future<void> setJwtToken(String employeeCode, String token) async {
    await _tokens!.write('$_keyJwtPrefix$employeeCode', token);
  }

  static Future<String?> getJwtToken(String employeeCode) async {
    return _tokens?.read('$_keyJwtPrefix$employeeCode');
  }

  // FCM device token last registered with the backend for this user - lets
  // logout unregister the right token even after an app restart.
  static Future<void> setFcmToken(String employeeCode, String token) async {
    await _tokens!.write('$_keyFcmTokenPrefix$employeeCode', token);
  }

  static Future<String?> getFcmToken(String employeeCode) async {
    return _tokens?.read('$_keyFcmTokenPrefix$employeeCode');
  }

  // Role-based app tour ("walkthrough") - whether this employee has seen it
  // on this install. Distinct from the account-setup "onboarding completed"
  // flag in SecureStorageService (that one gates PIN/fingerprint setup, not
  // this feature-tour carousel). Local storage means it naturally resets on
  // uninstall/reinstall - no extra logic needed for that.
  static Future<void> setWalkthroughSeen(String employeeCode, bool seen) async {
    await _prefs?.setBool('$_keyWalkthroughSeenPrefix$employeeCode', seen);
  }

  static bool getWalkthroughSeen(String employeeCode) {
    return _prefs?.getBool('$_keyWalkthroughSeenPrefix$employeeCode') ?? false;
  }

  // Clear session data for user on logout. Deliberately leaves the
  // walkthrough-seen flag alone (see setWalkthroughSeen doc comment):
  // logout/login is a normal returning-user flow, not a "reset". The app
  // lock (PIN/biometric) lives in SecureStorageService and is device-level,
  // not per-user, so it's untouched by logout entirely - see
  // AuthViewModel.clearActiveUser.
  static Future<void> clear(String employeeCode) async {
    await _tokens?.clear(employeeCode);
  }
}
