import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Working Hours / Timesheet module. Builds
/// `/api/work-logs/**` requests on top of the shared [ApiService]. Response
/// decoding and domain mapping live in [WorkLogRepository].
class WorkLogApiService {
  final ApiService _apiService = ApiService();

  String _buildQuery(Map<String, String?> params) {
    final filtered = <String, String>{};
    params.forEach((key, value) {
      if (value != null && value.isNotEmpty) filtered[key] = value;
    });
    if (filtered.isEmpty) return '';
    return '?${Uri(queryParameters: filtered).query}';
  }

  /// `GET /work-logs/reminder` - whether the previous working day's entry is
  /// still missing, for the "Missed Previous Day" popup.
  Future<http.Response> getPendingReminder({String? token}) {
    return _apiService.get(ApiConstants.workLogReminder, token: token);
  }

  /// `GET /work-logs/my` - the current employee/team leader's own timesheets.
  Future<http.Response> getMyWorkLogs({
    String? token,
    int? moduleId,
    String? status,
    String? fromDate,
    String? toDate,
  }) {
    final query = _buildQuery({
      'moduleId': moduleId?.toString(),
      'status': status,
      'fromDate': fromDate,
      'toDate': toDate,
    });
    return _apiService.get('${ApiConstants.myWorkLogs}$query', token: token);
  }

  /// `GET /work-logs` - the Team Leader's approval queue (scoped server-side
  /// to projects they lead).
  Future<http.Response> getWorkLogsForApproval({
    String? token,
    int? moduleId,
    int? employeeId,
    String? status,
    String? fromDate,
    String? toDate,
  }) {
    final query = _buildQuery({
      'moduleId': moduleId?.toString(),
      'employeeId': employeeId?.toString(),
      'status': status,
      'fromDate': fromDate,
      'toDate': toDate,
    });
    return _apiService.get('${ApiConstants.workLogs}$query', token: token);
  }

  Future<http.Response> getWorkLogById(String id, {String? token}) {
    return _apiService.get(ApiConstants.workLogById(id), token: token);
  }

  Future<http.Response> submitWorkLog(
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.post(ApiConstants.workLogs, body, token: token);
  }

  Future<http.Response> approveWorkLog(String id, {String? token}) {
    return _apiService.put(ApiConstants.approveWorkLog(id), const {}, token: token);
  }

  Future<http.Response> rejectWorkLog(
    String id,
    String rejectionReason, {
    String? token,
  }) {
    return _apiService.put(
      ApiConstants.rejectWorkLog(id),
      {'rejectionReason': rejectionReason},
      token: token,
    );
  }
}
