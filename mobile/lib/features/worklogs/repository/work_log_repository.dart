import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../auth/model/api_result.dart';
import '../model/create_work_log_request.dart';
import '../model/work_log.dart';
import '../model/work_log_reminder.dart';
import '../service/work_log_api_service.dart';

class WorkLogRepository {
  final WorkLogApiService _apiService = WorkLogApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// The stored JWT for whichever employee is currently signed in - needed
  /// because `/api/work-logs/**` requires `Authentication` on the backend
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
        message: success
            ? (body["message"] ?? successMessage)
            : (_fieldValidationMessage(body["message"], rawData) ?? "Unknown error"),
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

  /// Bean-validation failures (e.g. a `@Digits`/`@NotBlank` miss on the
  /// request body) come back from the backend as the generic top-level
  /// `"message": "Validation failed"`, with the actual per-field reason
  /// (e.g. "Hours worked must be entered in hours, minutes, and seconds
  /// only") only in `data`, a `{field: message}` map (see
  /// `GlobalExceptionHandler#handleValidation`). Surface the first real
  /// field message instead of the generic one whenever that shape shows up,
  /// so the user sees why the request actually failed.
  String? _fieldValidationMessage(dynamic message, dynamic rawData) {
    if (message == "Validation failed" &&
        rawData is Map &&
        rawData.isNotEmpty) {
      final firstMessage = rawData.values.first;
      if (firstMessage is String && firstMessage.isNotEmpty) {
        return firstMessage;
      }
    }
    return message as String?;
  }

  List<WorkLog> _mapWorkLogList(dynamic data) => (data as List)
      .map((json) => WorkLog.fromJson(json as Map<String, dynamic>))
      .toList();

  /// `GET /work-logs/reminder` - whether the previous working day's entry is
  /// still missing, for the "Missed Previous Day" popup on
  /// [TimesheetListScreen].
  Future<ApiResult> getPendingReminder() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getPendingReminder(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Reminder status loaded successfully",
      mapData: (data) =>
          WorkLogReminder.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `GET /work-logs/my` - list for [TimesheetListScreen] (Employee / Team
  /// Leader).
  Future<ApiResult> getMyWorkLogs({int? moduleId, String? status}) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getMyWorkLogs(
        token: token,
        moduleId: moduleId,
        status: status,
      ),
      isSuccess: (code) => code == 200,
      successMessage: "Timesheets loaded successfully",
      mapData: _mapWorkLogList,
    );
  }

  /// `GET /work-logs` - the approval queue for [TimesheetApprovalListScreen]
  /// (Team Leader only).
  Future<ApiResult> getWorkLogsForApproval({
    int? moduleId,
    int? employeeId,
    String? status,
  }) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getWorkLogsForApproval(
        token: token,
        moduleId: moduleId,
        employeeId: employeeId,
        status: status,
      ),
      isSuccess: (code) => code == 200,
      successMessage: "Timesheets loaded successfully",
      mapData: _mapWorkLogList,
    );
  }

  /// `GET /work-logs/{id}` - full detail for the timesheet details screen.
  Future<ApiResult> getWorkLogDetails(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getWorkLogById(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Timesheet details loaded successfully",
      mapData: (data) => WorkLog.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `POST /work-logs` - submits a new timesheet entry (Employee only).
  Future<ApiResult> submitWorkLog(CreateWorkLogRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.submitWorkLog(request.toJson(), token: token),
      isSuccess: (code) => code == 200 || code == 201,
      mapData: (data) => WorkLog.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /work-logs/{id}/approve` (Team Leader only).
  Future<ApiResult> approveWorkLog(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.approveWorkLog(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Timesheet approved successfully",
      mapData: (data) => WorkLog.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /work-logs/{id}/reject` (Team Leader only).
  Future<ApiResult> rejectWorkLog(int id, String rejectionReason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.rejectWorkLog(id.toString(), rejectionReason, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Timesheet rejected successfully",
      mapData: (data) => WorkLog.fromJson(data as Map<String, dynamic>),
    );
  }
}
