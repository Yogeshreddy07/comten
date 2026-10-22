import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  // EncryptedSharedPreferences avoids the Android Keystore decryption
  // errors (BadPaddingException after an app restart) that the default v9
  // backing intermittently throws - those errors were what kept "losing"
  // the biometric enrollment between app launches.
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // App lock (PIN + fingerprint) is a device-level lock, not a per-account
  // credential: it gates access to the app on this device regardless of
  // which account is signed in, so these two keys are deliberately global -
  // not scoped to an employee code. See AuthViewModel's app-lock methods.
  static const String _keyAppLockPin = 'app_lock_pin';
  static const String _keyAppLockBiometricEnabled = 'app_lock_biometric_enabled';

  static const String _keyActiveEmployeeCode = 'active_employee_code';
  static const String _keyOnboardingCompletedPrefix = 'onboarding_completed_';
  static const String _keyWalkthroughSeenPrefix = 'walkthrough_seen_';

  // In-memory mirror of the active employee code - every repository's
  // `_currentToken()` reads this via getActiveEmployeeCode() before *every*
  // authenticated API call, which otherwise means a Keystore-backed
  // platform-channel round trip per request for a value that only ever
  // changes on login/logout. Static (not an instance field) because each
  // repository constructs its own `SecureStorageService()` instance, so
  // only a class-level cache is actually shared across all of them. Reset
  // to "not yet cached" on process start, so a fresh app launch still reads
  // whatever was actually persisted from the previous session exactly
  // once, before relying on the cache.
  static String? _cachedActiveEmployeeCode;
  static bool _activeEmployeeCodeCached = false;

  /// Drops only the unreadable key on failure. The previous recovery
  /// (`deleteAll()`) treated one corrupt entry as total corruption and wiped
  /// every stored value - including the biometric enrollment - whenever the
  /// Keystore hiccuped on a single read.
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      try {
        await _storage.delete(key: key);
      } catch (_) {
        // Nothing further we can do if clearing the entry also fails.
      }
      return null;
    }
  }

  Future<void> saveActiveEmployeeCode(String employeeCode) async {
    await _storage.write(key: _keyActiveEmployeeCode, value: employeeCode);
    _cachedActiveEmployeeCode = employeeCode;
    _activeEmployeeCodeCached = true;
  }

  Future<String?> getActiveEmployeeCode() async {
    if (_activeEmployeeCodeCached) return _cachedActiveEmployeeCode;
    final value = await _safeRead(_keyActiveEmployeeCode);
    _cachedActiveEmployeeCode = value;
    _activeEmployeeCodeCached = true;
    return value;
  }

  Future<void> saveOnboardingCompleted(String employeeCode, bool completed) async {
    await _storage.write(key: '$_keyOnboardingCompletedPrefix$employeeCode', value: completed.toString());
  }

  Future<bool> getOnboardingCompleted(String employeeCode) async {
    final val = await _safeRead('$_keyOnboardingCompletedPrefix$employeeCode');
    return val == 'true';
  }

  Future<void> saveWalkthroughSeen(String employeeCode, bool seen) async {
    await _storage.write(key: '$_keyWalkthroughSeenPrefix$employeeCode', value: seen.toString());
  }

  Future<bool> getWalkthroughSeen(String employeeCode) async {
    final val = await _safeRead('$_keyWalkthroughSeenPrefix$employeeCode');
    return val == 'true';
  }

  Future<void> clearActiveUser() async {
    await _storage.delete(key: _keyActiveEmployeeCode);
    _cachedActiveEmployeeCode = null;
    _activeEmployeeCodeCached = true;
  }

  /// The device's app-lock PIN - shared by every account signed in on this
  /// device (app lock protects the app, not a specific account). Null means
  /// no app lock has been configured on this device yet.
  Future<void> saveAppLockPin(String pin) async {
    await _storage.write(key: _keyAppLockPin, value: pin);
  }

  Future<String?> getAppLockPin() async {
    return await _safeRead(_keyAppLockPin);
  }

  Future<void> setAppLockBiometricEnabled(bool enabled) async {
    await _storage.write(
        key: _keyAppLockBiometricEnabled, value: enabled.toString());
  }

  Future<bool> getAppLockBiometricEnabled() async {
    final val = await _safeRead(_keyAppLockBiometricEnabled);
    return val == 'true';
  }
}
