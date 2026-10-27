import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../auth/model/api_result.dart';
import '../model/delay_request.dart';
import '../model/notification_item.dart';
import '../model/submit_delay_request.dart';
import '../service/notification_api_service.dart';

class NotificationRepository {
  final NotificationApiService _apiService = NotificationApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// The stored JWT for whichever employee is currently signed in - needed
  /// because `/api/notifications/**` requires `Authentication` on the
  /// backend (see `SecurityConfig`: `.anyRequest().authenticated()`).
  Future<String?> _currentToken() async {
    final employeeCode = await _secureStorage.getActiveEmployeeCode();
    if (employeeCode == null || employeeCode.isEmpty) return null;
    return PreferenceUtil.getJwtToken(employeeCode);
  }

  /// Shared request-and-decode path used by every method below - same
  /// contract as `ProjectRepository._request`.
  Future<ApiResult> _request(
    Future<http.Response> Function() call, {
    required bool Function(int statusCode) isSuccess,
    dynamic Function(dynamic data)? mapData,
    String successMessage = "Success",
  }) async {
    try {
      final response = await call();
      final success = isSuccess(response.statusCode);

      if (response.body.isEmpty) {
        return ApiResult(
          success: success,
          message: success ? successMessage : "Server returned ${response.statusCode}",
        );
      }

      final body = jsonDecode(response.body);
      final rawData = body["data"];

      return ApiResult(
        success: success,
        message: body["message"] ?? (success ? successMessage : "Unknown error"),
        data: success && rawData != null && mapData != null
            ? mapData(rawData)
            : (success ? rawData : null),
      );
    } catch (e) {
      return ApiResult(
        success: false,
        message: "Unable to connect to server.",
      );
    }
  }

  /// `GET /notifications`.
  Future<ApiResult> getNotifications() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getNotifications(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Notifications loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => NotificationItem.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `GET /notifications/unread-count`.
  Future<ApiResult> getUnreadCount() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getUnreadCount(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Unread count loaded successfully",
      mapData: (data) => (data as num).toInt(),
    );
  }

  /// `PUT /notifications/{id}/read`.
  Future<ApiResult> markAsRead(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.markAsRead(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Notification marked as read",
      mapData: (data) => NotificationItem.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `POST /notifications/delay-requests` (Team Lead only).
  Future<ApiResult> submitDelayRequest(SubmitDelayRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.submitDelayRequest(request.toJson(), token: token),
      isSuccess: (code) => code == 200 || code == 201,
      successMessage: "Reason for delay submitted successfully",
      mapData: (data) => NotificationItem.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `GET /delay-requests/{id}` - the request's current approval state.
  Future<ApiResult> getDelayRequest(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getDelayRequest(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Delay request loaded",
      mapData: (data) => DelayRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /delay-requests/{id}/approve` (Captain / Project Controller).
  Future<ApiResult> approveDelayRequest(int id, String reason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.approveDelayRequest(id.toString(), {'reason': reason}, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Reason for delay approved",
      mapData: (data) => DelayRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /delay-requests/{id}/reject` (Captain / Project Controller).
  Future<ApiResult> rejectDelayRequest(int id, String reason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.rejectDelayRequest(id.toString(), {'reason': reason}, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Reason for delay rejected",
      mapData: (data) => DelayRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `POST /notifications/device-tokens` - registers this device for Home
  /// Screen push notifications.
  Future<ApiResult> registerDeviceToken(String deviceToken) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.registerDeviceToken(deviceToken, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Device registered for push notifications",
    );
  }

  /// `POST /notifications/device-tokens/unregister` - called on logout so a
  /// signed-out device stops receiving pushes for this account.
  Future<ApiResult> unregisterDeviceToken(String deviceToken) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.unregisterDeviceToken(deviceToken, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Device unregistered from push notifications",
    );
  }
}
