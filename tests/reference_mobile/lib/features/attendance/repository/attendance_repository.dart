import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../auth/model/api_result.dart';
import '../model/attendance.dart';
import '../model/check_in_request.dart';
import '../model/check_out_request.dart';
import '../model/team_attendance_entry.dart';
import '../service/attendance_api_service.dart';

class AttendanceRepository {
  final AttendanceApiService _apiService = AttendanceApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// The stored JWT for whichever employee is currently signed in - needed
  /// because `/api/attendance/**` requires `Authentication` on the backend
  /// (see `SecurityConfig`: `.anyRequest().authenticated()`).
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

  /// `POST /attendance/check-in`.
  Future<ApiResult> checkIn(CheckInRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.checkIn(request.toJson(), token: token),
      isSuccess: (code) => code == 200 || code == 201,
      mapData: (data) => Attendance.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /attendance/check-out`.
  Future<ApiResult> checkOut(CheckOutRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.checkOut(request.toJson(), token: token),
      isSuccess: (code) => code == 200,
      mapData: (data) => Attendance.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `GET /attendance/today` - `result.data` is `null` (with `success: true`)
  /// when the employee hasn't checked in yet today, distinguishing "no
  /// record" from a network/server error.
  Future<ApiResult> getTodayAttendance() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getTodayAttendance(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Today's attendance loaded successfully",
      mapData: (data) => Attendance.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `GET /attendance/team` - every member of a project the Team Leader
  /// leads, with their attendance status for [date] (defaults to today on
  /// the backend when omitted).
  Future<ApiResult> getTeamAttendance({DateTime? date}) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getTeamAttendance(
        token: token,
        date: date != null ? _formatDate(date) : null,
      ),
      isSuccess: (code) => code == 200,
      successMessage: "Team attendance loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => TeamAttendanceEntry.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
