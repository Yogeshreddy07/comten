import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Attendance module. Builds `/api/attendance/**`
/// requests on top of the shared [ApiService]. Response decoding and domain
/// mapping live in [AttendanceRepository].
class AttendanceApiService {
  final ApiService _apiService = ApiService();

  Future<http.Response> checkIn(Map<String, dynamic> body, {String? token}) {
    return _apiService.post(ApiConstants.attendanceCheckIn, body, token: token);
  }

  Future<http.Response> checkOut(Map<String, dynamic> body, {String? token}) {
    return _apiService.put(ApiConstants.attendanceCheckOut, body, token: token);
  }

  Future<http.Response> getTodayAttendance({String? token}) {
    return _apiService.get(ApiConstants.attendanceToday, token: token);
  }

  Future<http.Response> getTeamAttendance({
    String? token,
    String? date,
  }) {
    final query = (date != null && date.isNotEmpty)
        ? '?${Uri(queryParameters: {'date': date}).query}'
        : '';
    return _apiService.get('${ApiConstants.attendanceTeam}$query', token: token);
  }
}
