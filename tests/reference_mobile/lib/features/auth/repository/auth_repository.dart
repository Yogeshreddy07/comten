import 'dart:convert';

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../model/api_result.dart';

class AuthRepository {
  final ApiService _apiService = ApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// The stored JWT for whichever employee is currently signed in - needed
  /// for every endpoint that now requires `Authentication` on the backend
  /// (see `SecurityConfig`: `.anyRequest().authenticated()`).
  Future<String?> _currentToken() async {
    final employeeCode = await _secureStorage.getActiveEmployeeCode();
    if (employeeCode == null || employeeCode.isEmpty) return null;
    return PreferenceUtil.getJwtToken(employeeCode);
  }

  /// Shared POST-and-decode path used by every auth call below. The backend's
  /// [ApiResponse] wrapper always sets an explicit `success` boolean (both on
  /// its success() and error() factories), so that field - not the HTTP
  /// status code - is the authoritative success signal.
  Future<ApiResult> _post(
    String endpoint,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async {
    try {
      final response = await _apiService.post(
        endpoint,
        body,
        token: token,
        timeout: timeout,
      );

      if (response.body.isEmpty) {
        return ApiResult(
          success: false,
          message: "Server returned ${response.statusCode}",
        );
      }

      final decoded = jsonDecode(response.body);

      return ApiResult(
        success: decoded["success"] ?? false,
        message: decoded["message"] ?? "Unknown error",
        data: decoded["data"],
      );
    } catch (e) {
      return ApiResult(success: false, message: "Unable to connect to server.");
    }
  }

  String _formatPhone(String phone) {
    final trimmed = phone.trim();
    return trimmed.startsWith('+91') ? trimmed : '+91$trimmed';
  }

  // --- SIGNUP FLOW ---

  Future<ApiResult> verifyTempPassword({
    required String employeeCode,
    required String tempPassword,
  }) {
    return _post(ApiConstants.authVerifyTempPassword, {
      "employeeCode": employeeCode,
      "tempPassword": tempPassword,
    });
  }

  /// `signupToken` comes from [verifyTempPassword] and is mandatory - the backend
  /// rejects the request without it (the endpoint is public, so the token is what
  /// proves the caller knew this account's temporary password).
  Future<ApiResult> setPassword({
    required String employeeCode,
    required String signupToken,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _post(ApiConstants.authSetPassword, {
      "employeeCode": employeeCode,
      "signupToken": signupToken,
      "newPassword": newPassword,
      "confirmPassword": confirmPassword,
    });
  }

  bool _isTransientFailure(String message) {
    return message.startsWith("An unexpected error occurred") ||
        message == "Unable to connect to server." ||
        message.startsWith("Server returned");
  }

  /// Submits a Firebase Auth phone-sign-in ID token - obtained natively on-device via
  /// [PhoneVerificationChannel] after the user completes SMS OTP verification, not sent by the
  /// backend - for the backend to validate via the Firebase Admin SDK.
  Future<ApiResult> verifyPhoneCode({
    required String employeeCode,
    required String phone,
    required String idToken,
  }) {
    return _post(ApiConstants.authVerifyPhone, {
      "employeeCode": employeeCode,
      "phoneNumber": _formatPhone(phone),
      "idToken": idToken,
    });
  }

  // --- LOGIN FLOW ---

  Future<ApiResult> login({
    required String employeeCode,
    required String password,
  }) {
    return _post(ApiConstants.authLogin, {
      "employeeCode": employeeCode,
      "password": password,
    }, timeout: const Duration(seconds: ApiConstants.loginTimeoutSeconds));
  }

  // --- FORGOT PASSWORD FLOW ---

  Future<ApiResult> sendForgotPasswordOtp({
    required String employeeCode,
    required String email,
  }) async {
    // Same dedicated timeout as the phone OTP send below: dispatching an OTP through an
    // external provider (email here, SMS there) is slower than a typical CRUD call,
    // especially on a cold backend start.
    const timeout = Duration(seconds: ApiConstants.otpSendTimeoutSeconds);
    final body = {
      "employeeCode": employeeCode,
      "email": email,
    };

    var result = await _post(
      ApiConstants.authForgotPasswordSendOtp,
      body,
      timeout: timeout,
    );

    // One silent retry, matching [sendOtp]'s treatment of the phone OTP - this send is the
    // app's first call after opening, so it is the one that eats a cold backend start and
    // times out despite the backend completing and mailing the code. Retrying a POST is
    // normally unsafe, but this specific endpoint is idempotent by design: while a usable
    // OTP is still outstanding the backend returns success without generating or mailing a
    // second one (see AuthServiceImpl#sendForgotPasswordOtp), so the retry either reaches a
    // backend that never got the first request, or confirms the one that did.
    if (!result.success && _isTransientFailure(result.message)) {
      result = await _post(
        ApiConstants.authForgotPasswordSendOtp,
        body,
        timeout: timeout,
      );
    }

    return result;
  }

  Future<ApiResult> verifyForgotPasswordOtp({
    required String employeeCode,
    required String email,
    required String otp,
  }) {
    return _post(ApiConstants.authForgotPasswordVerifyOtp, {
      "employeeCode": employeeCode,
      "email": email,
      "otp": otp,
    });
  }

  Future<ApiResult> resetForgotPassword({
    required String employeeCode,
    required String resetToken,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _post(ApiConstants.authForgotPasswordReset, {
      "employeeCode": employeeCode,
      "resetToken": resetToken,
      "newPassword": newPassword,
      "confirmPassword": confirmPassword,
    });
  }

  // --- SETTINGS: ACCOUNT / SECURITY ---

  Future<ApiResult> changePassword({
    String? currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final token = await _currentToken();
    return _put(
      ApiConstants.authChangePassword,
      {
        "oldPassword": currentPassword ?? "",
        "newPassword": newPassword,
        "confirmPassword": confirmPassword,
      },
      token: token,
    );
  }

  Future<ApiResult> logout() async {
    final token = await _currentToken();
    return _post(ApiConstants.authLogout, const {}, token: token);
  }

  Future<ApiResult> getSettings() async {
    final token = await _currentToken();
    return _get(ApiConstants.usersMe, token: token);
  }

  Future<ApiResult> _put(
    String endpoint,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    try {
      final response = await _apiService.put(endpoint, body, token: token);

      if (response.body.isEmpty) {
        return ApiResult(
          success: false,
          message: "Server returned ${response.statusCode}",
        );
      }

      final decoded = jsonDecode(response.body);

      return ApiResult(
        success: decoded["success"] ?? false,
        message: decoded["message"] ?? "Unknown error",
        data: decoded["data"],
      );
    } catch (e) {
      return ApiResult(success: false, message: "Unable to connect to server.");
    }
  }

  Future<ApiResult> _get(String endpoint, {String? token}) async {
    try {
      final response = await _apiService.get(endpoint, token: token);

      if (response.body.isEmpty) {
        return ApiResult(
          success: false,
          message: "Server returned ${response.statusCode}",
        );
      }

      final decoded = jsonDecode(response.body);

      return ApiResult(
        success: decoded["success"] ?? false,
        message: decoded["message"] ?? "Unknown error",
        data: decoded["data"],
      );
    } catch (e) {
      return ApiResult(success: false, message: "Unable to connect to server.");
    }
  }

  /// Signup flow: requires the signup token from [verifyTempPassword] - the
  /// backend will not hand out a phone number without it (it is a public,
  /// pre-login endpoint). Post-login re-verification flow (phone left
  /// unverified from a previous session): no signup token exists then, so the
  /// already-issued login JWT is sent instead and the backend accepts either.
  Future<ApiResult> getPhoneNumber(String employeeCode, String signupToken) async {
    try {
      final token = await _currentToken();
      final response = await _apiService.get(
        '/users/phone-number/$employeeCode'
        '?signupToken=${Uri.encodeQueryComponent(signupToken)}',
        token: token,
      );
      final body = jsonDecode(response.body);
      return ApiResult(
        success: response.statusCode == 200,
        message: body["message"] ?? "Unknown error",
        data: body["data"],
      );
    } catch (e) {
      return ApiResult(success: false, message: "Unable to connect to server.");
    }
  }
}
