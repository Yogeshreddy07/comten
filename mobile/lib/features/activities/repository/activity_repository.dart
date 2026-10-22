import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../auth/model/api_result.dart';
import '../model/activity.dart';
import '../service/activity_api_service.dart';

class ActivityRepository {
  final ActivityApiService _apiService = ActivityApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  Future<String?> _currentToken() async {
    final employeeCode = await _secureStorage.getActiveEmployeeCode();
    if (employeeCode == null || employeeCode.isEmpty) return null;
    return PreferenceUtil.getJwtToken(employeeCode);
  }

  /// Shared request-and-decode path - same contract as
  /// `ProjectRepository._request`/`EmployeeRepository._request`.
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

  /// `GET /activities` - active activities, ordered by name.
  Future<ApiResult> getActivities() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getActivities(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Activities loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => Activity.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `POST /activities`.
  Future<ApiResult> createActivity(String name) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.createActivity({'name': name}, token: token),
      isSuccess: (code) => code == 200 || code == 201,
      mapData: (data) => Activity.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `DELETE /activities/{id}`.
  Future<ApiResult> deleteActivity(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.deleteActivity(id.toString(), token: token),
      isSuccess: (code) => code == 200,
    );
  }
}
