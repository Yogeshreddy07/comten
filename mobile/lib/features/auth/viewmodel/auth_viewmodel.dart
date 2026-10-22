import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/account_cache.dart';
import 'package:flutter/material.dart';
import '../../../core/services/phone_verification_channel.dart';
import '../../../core/utils/biometric_helper.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../../core/utils/preference_util.dart';
import '../../../shared/enums/user_role.dart';
import '../model/signup_session.dart';
import '../model/api_result.dart';
import '../repository/auth_repository.dart';
import '../model/reset_password_session.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthRepository _repository;
  final SecureStorageService _secureStorage;
  final PhoneVerificationChannel _phoneVerificationChannel;
  AuthViewModel({
    required AuthRepository repository,
    required SecureStorageService secureStorage,
    PhoneVerificationChannel? phoneVerificationChannel,
  }) : _repository = repository,
       _secureStorage = secureStorage,
       _phoneVerificationChannel =
           phoneVerificationChannel ?? PhoneVerificationChannel() {
    checkBiometricSupport();
  }
  SignupSession? _signupSession;
  ResetPasswordSession? _resetPasswordSession;
  String? _employeeCode;
  bool _isLoading = false;

  bool _isBiometricsSupported = false;
  // Whether this device's app lock has biometric unlock turned on - a
  // device-wide fact, not tied to whichever account happens to be signed
  // in (see SecureStorageService's app-lock keys).
  bool _isBiometricEnabled = false;

  UserRole? _role;
  String? _name;

  SignupSession? get signupSession => _signupSession;
  String get employeeCode => _employeeCode ?? "";
  bool get isLoading => _isLoading;

  bool get isBiometricsSupported => _isBiometricsSupported;
  bool get isBiometricEnabled => _isBiometricEnabled;

  /// The authenticated user's role, refreshed from the backend on every
  /// login/verification response (see [_captureIdentity]). Defaults to the
  /// least-privileged [UserRole.employee] if no role has been received yet.
  UserRole get role => _role ?? UserRole.employee;

  /// Best available display name for greetings - falls back to the
  /// employee code, never a hardcoded placeholder.
  String get displayName {
    final name = _name;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    return employeeCode;
  }

  /// Reads `role`/`name` out of an `AuthResponse`-shaped API result (every
  /// auth endpoint returns these via the backend's `AuthMapper`) and updates
  /// the current identity. Called from every place that logs a user in or
  /// re-verifies them, so [role] is always current by the time a screen
  /// needs to decide which dashboard to open.
  void _captureIdentity(dynamic data) {
    if (data is! Map) return;
    final roleValue = data['role'];
    if (roleValue is String) {
      _role = UserRoleX.fromBackendValue(roleValue);
    }
    final nameValue = data['name'];
    if (nameValue is String && nameValue.trim().isNotEmpty) {
      _name = nameValue;
    }
  }

  Future<ApiResult> verifyTempPassword({
    required String employeeCode,
    required String tempPassword,
  }) async {
    _setLoading(true);

    try {
      final result = await _repository.verifyTempPassword(
        employeeCode: employeeCode,
        tempPassword: tempPassword,
      );

      if (result.success && result.data != null) {
        _signupSession = SignupSession.fromJson(result.data);
        _captureIdentity(result.data);
      }

      return result;
    } finally {
      _setLoading(false);
    }
  }

  Future<ApiResult> setPassword({
    required String newPassword,
    required String confirmPassword,
  }) async {
    _setLoading(true);

    try {
      if (_signupSession == null) {
        return ApiResult(
          success: false,
          message:
              "Signup session expired. Please activate your account again.",
        );
      }

      return await _repository.setPassword(
        employeeCode: _signupSession!.employeeCode,
        signupToken: _signupSession!.signupToken,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );
    } finally {
      _setLoading(false);
    }
  }

  /// Native verification state changes (code sent / auto-verified / failed) for whichever
  /// [startPhoneVerification]/[resendPhoneVerificationCode] call is currently in flight -
  /// the phone verification screen listens to this to drive its UI.
  Stream<PhoneVerificationEvent> get phoneVerificationEvents =>
      _phoneVerificationChannel.events;

  /// Triggers Firebase to send an SMS code to [phoneNumber] (E.164 format, e.g. "+91..."). The
  /// outcome (code sent / auto-verified / failed) arrives on [phoneVerificationEvents].
  ///
  /// Also updates [phoneNumber] to the number actually being verified - the user may have typed
  /// a different number than whatever [fetchPhoneNumber] last returned, and
  /// [confirmPhoneVerification] must submit the same number Firebase verified, or the backend's
  /// equality check against the employee's registered number will reject it.
  Future<void> startPhoneVerification(String phoneNumber) {
    _phoneNumber = phoneNumber;
    return _phoneVerificationChannel.startVerification(phoneNumber);
  }

  /// Re-sends the SMS code to the same number verification was last started for.
  Future<void> resendPhoneVerificationCode(String phoneNumber) {
    _phoneNumber = phoneNumber;
    return _phoneVerificationChannel.resendCode(phoneNumber);
  }

  /// Submits the user-entered SMS [code] (or, for auto-verification, an [idToken] obtained
  /// directly from a [PhoneAutoVerified] event) to the backend for verification.
  Future<ApiResult> confirmPhoneVerification({
    String? verificationId,
    String? code,
    String? idToken,
  }) async {
    _setLoading(true);

    try {
      if (_signupSession == null) {
        return ApiResult(
          success: false,
          message:
              "Signup session expired. Please activate your account again.",
        );
      }
      final phone = _phoneNumber;
      if (phone == null || phone.isEmpty) {
        return ApiResult(
          success: false,
          message: "No registered phone number found.",
        );
      }

      String verifiedIdToken;
      if (idToken != null) {
        verifiedIdToken = idToken;
      } else if (verificationId != null && code != null) {
        try {
          verifiedIdToken = await _phoneVerificationChannel.submitCode(
            verificationId: verificationId,
            code: code,
          );
        } on PhoneVerificationException catch (e) {
          return ApiResult(success: false, message: e.message);
        }
      } else {
        return ApiResult(
          success: false,
          message: "Enter the verification code.",
        );
      }

      final result = await _repository.verifyPhoneCode(
        employeeCode: _signupSession!.employeeCode,
        phone: phone,
        idToken: verifiedIdToken,
      );
      if (result.success) {
        _captureIdentity(result.data);
      }
      return result;
    } finally {
      _setLoading(false);
    }
  }

  // --- APP LOCK (device-level PIN + fingerprint) ---
  //
  // App lock protects the app on this device, not a specific account: it's
  // stored purely locally (SecureStorageService) and never touches the
  // backend. Once any account configures it, every account signed in on
  // this device shares the same lock - see hasAppLockConfigured().

  /// Whether this device already has an app-lock PIN configured. Fingerprint
  /// is an optional add-on on top of the PIN, never a substitute for it, so
  /// checking the PIN alone is enough to know whether onboarding needs to
  /// show the setup screens.
  Future<bool> hasAppLockConfigured() async {
    final pin = await _secureStorage.getAppLockPin();
    return pin != null && pin.isNotEmpty;
  }

  /// Sets this device's app-lock PIN - shared by every account on this
  /// device, overwriting any previous one.
  Future<void> setAppLockPin(String pin) async {
    await _secureStorage.saveAppLockPin(pin);
  }

  /// Verifies [pin] against this device's stored app-lock PIN. Purely local:
  /// unlocking never calls the backend, since a session is already active -
  /// this just confirms the PIN and lets the caller reveal it.
  Future<bool> verifyAppLockPin(String pin) async {
    final stored = await _secureStorage.getAppLockPin();
    return stored != null && stored.isNotEmpty && stored == pin;
  }

  Future<void> loadAppLockSettings() async {
    _isBiometricEnabled = await _secureStorage.getAppLockBiometricEnabled();
    notifyListeners();
  }

  /// Confirms biometric hardware works via the OS prompt, then turns it on
  /// as this device's app-lock method (in addition to the PIN, never
  /// instead of it).
  Future<ApiResult> enableAppLockBiometric() async {
    final bioResult = await BiometricHelper.authenticate(
      reason: 'Scan your fingerprint to enable biometric app lock',
    );

    if (bioResult == BiometricResult.hardwareUnavailable) {
      return ApiResult(
        success: false,
        message: "Biometric hardware is unavailable on this device.",
      );
    } else if (bioResult == BiometricResult.notEnrolled) {
      return ApiResult(
        success: false,
        message: "No fingerprints are enrolled on this device.",
      );
    } else if (bioResult == BiometricResult.failed) {
      return ApiResult(
        success: false,
        message: "Biometric authentication failed or was cancelled.",
      );
    }

    await _secureStorage.setAppLockBiometricEnabled(true);
    _isBiometricEnabled = true;
    notifyListeners();
    return ApiResult(
      success: true,
      message: "Biometric app lock enabled successfully",
    );
  }

  Future<ApiResult> disableAppLockBiometric() async {
    await _secureStorage.setAppLockBiometricEnabled(false);
    _isBiometricEnabled = false;
    notifyListeners();
    return ApiResult(
      success: true,
      message: "Biometric app lock disabled successfully",
    );
  }

  /// Unlocks the app with the OS fingerprint prompt. Purely local, like
  /// [verifyAppLockPin]: no backend call, since the app is already signed
  /// in - this just confirms it's really the device owner and lets the
  /// caller reveal the existing session.
  Future<bool> unlockWithBiometrics() async {
    if (!_isBiometricEnabled) return false;
    final bioResult = await BiometricHelper.authenticate(
      reason: 'Scan your fingerprint to unlock the app',
    );
    return bioResult == BiometricResult.success;
  }

  /// Re-hydrates [role]/[name] from the backend for the account whose
  /// session is stored locally - needed after a cold start, since unlocking
  /// the app lock no longer performs a login that would otherwise refresh
  /// them. This is a plain authenticated profile fetch (same one the
  /// Settings screen makes), not a re-login: it requires no PIN/fingerprint
  /// and never blocks the local unlock gesture.
  Future<void> restoreSessionIdentity(String employeeCode) async {
    _employeeCode = employeeCode;
    final result = await _repository.getSettings();
    if (result.success && result.data != null) {
      _captureIdentity(result.data);
    }
    notifyListeners();
  }

  Future<ApiResult> login({
    required String employeeCode,
    required String password,
  }) async {
    if (_isLoading) {
      return ApiResult(success: false, message: "Already logging in...");
    }

    _setLoading(true);

    try {
      final result = await _repository.login(
        employeeCode: employeeCode,
        password: password,
      );

      if (result.success && result.data != null) {
        final token = result.data is Map ? result.data['token'] : null;
        if (token is! String || token.isEmpty) {
          return ApiResult(success: false, message: 'Login session unavailable. Please try again.');
        }
        try {
          await _saveTokenFromResult(employeeCode, result);
          await _secureStorage.saveActiveEmployeeCode(employeeCode);
        } catch (_) {
          try { await PreferenceUtil.clear(employeeCode); } catch (_) {}
          return ApiResult(success: false, message: 'Unable to save login securely. Please try again.');
        }
        _employeeCode = employeeCode;
        // Logging in is not the signup flow, so there is no signup token here -
        // set-password is unreachable from this path by design (the backend
        // rejects a blank token).
        _signupSession = SignupSession(
          employeeCode: employeeCode,
          signupToken: '',
        );
        _captureIdentity(result.data);
        // The app lock itself is device-wide, not per-account, but reload
        // it anyway so the in-memory flag reflects this device's actual
        // setting right after login (e.g. first login on a fresh install).
        await loadAppLockSettings();
      }

      return result;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _saveTokenFromResult(
    String employeeCode,
    ApiResult result,
  ) async {
    final token = result.data is Map ? result.data['token'] as String? : null;
    if (token != null && token.isNotEmpty) {
      await PreferenceUtil.setJwtToken(employeeCode, token);
    }
  }

  /// Token for the currently active user, to attach to authenticated API calls.
  Future<String?> getToken(String employeeCode) async {
    return PreferenceUtil.getJwtToken(employeeCode);
  }

  Future<void> saveActiveEmployeeCode(String employeeCode) async {
    await _secureStorage.saveActiveEmployeeCode(employeeCode);
    _employeeCode = employeeCode;
    notifyListeners();
  }

  Future<String?> getActiveEmployeeCode() async {
    return await _secureStorage.getActiveEmployeeCode();
  }

  Future<void> saveOnboardingCompleted(
    String employeeCode,
    bool completed,
  ) async {
    await _secureStorage.saveOnboardingCompleted(employeeCode, completed);
  }

  Future<bool> getOnboardingCompleted(String employeeCode) async {
    return await _secureStorage.getOnboardingCompleted(employeeCode);
  }

  /// Marks the role-based first-login walkthrough as seen for
  /// [employeeCode] so [RoleDashboardNavigator.navigate] never shows it
  /// again for this user - see `features/walkthrough`.
  Future<void> saveWalkthroughSeen(String employeeCode) async {
    await _secureStorage.saveWalkthroughSeen(employeeCode, true);
  }

  Future<bool> getWalkthroughSeen(String employeeCode) async {
    return await _secureStorage.getWalkthroughSeen(employeeCode);
  }

  /// Logout cleanup. Deliberately leaves the device's app lock (PIN +
  /// biometric toggle) untouched - it's not part of this account's session,
  /// so logging out must not disable or reset it; only the explicit
  /// Settings screens change it.
  Future<void> clearActiveUser({String? employeeCode}) async {
    final code = employeeCode ?? _employeeCode ?? await _secureStorage.getActiveEmployeeCode();
    await AccountCache.instance.clear();
    await FirebaseAuth.instance.signOut();
    await _secureStorage.clearActiveUser();
    if (code != null && code.isNotEmpty) {
      await PreferenceUtil.clear(code);
    }
    _employeeCode = null;
    _signupSession = null;
    _resetPasswordSession = null;
    _phoneNumber = null;
    _role = null;
    _name = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // FORGOT PASSWORD
  // ------------------------------------------------------------------

  Future<ApiResult> sendForgotPasswordOtp({
    required String employeeCode,
    required String email,
  }) async {
    _setLoading(true);

    try {
      return await _repository.sendForgotPasswordOtp(
        employeeCode: employeeCode,
        email: email,
      );
    } finally {
      _setLoading(false);
    }
  }

  Future<ApiResult> verifyForgotPasswordOtp({
    required String employeeCode,
    required String email,
    required String otp,
  }) async {
    _setLoading(true);

    try {
      final result = await _repository.verifyForgotPasswordOtp(
        employeeCode: employeeCode,
        email: email,
        otp: otp,
      );

      if (result.success && result.data != null) {
        _resetPasswordSession = ResetPasswordSession.fromJson(result.data);
      }

      return result;
    } finally {
      _setLoading(false);
    }
  }

  Future<ApiResult> resetForgotPassword({
    required String employeeCode,
    required String newPassword,
    required String confirmPassword,
  }) async {
    _setLoading(true);

    try {
      if (_resetPasswordSession == null) {
        return ApiResult(
          success: false,
          message: "Reset session expired. Please verify OTP again.",
        );
      }

      return await _repository.resetForgotPassword(
        employeeCode: employeeCode,
        resetToken: _resetPasswordSession!.resetToken,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      );
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> checkBiometricSupport() async {
    _isBiometricsSupported = await BiometricHelper.isHardwareAvailable();
    if (_isBiometricsSupported) {
      await loadAppLockSettings();
    } else {
      notifyListeners();
    }
  }

  String? _phoneNumber;
  String? get phoneNumber => _phoneNumber;

  Future<ApiResult> fetchPhoneNumber(String employeeCode) async {
    _setLoading(true);
    try {
      final result = await _repository.getPhoneNumber(
        employeeCode,
        _signupSession?.signupToken ?? '',
      );
      if (result.success && result.data != null) {
        _phoneNumber = result.data['phoneNumber'];
        notifyListeners();
      }
      return result;
    } finally {
      _setLoading(false);
    }
  }
}
