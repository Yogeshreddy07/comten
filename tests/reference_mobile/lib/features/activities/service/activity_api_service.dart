import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Activities module - master list of Billable/
/// Non-Billable activities a Project Controller assigns to projects.
/// Response decoding and domain mapping live in [ActivityRepository].
class ActivityApiService {
  final ApiService _apiService = ApiService();

  Future<http.Response> getActivities({String? token}) {
    return _apiService.get(ApiConstants.activities, token: token);
  }

  Future<http.Response> createActivity(
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.post(ApiConstants.activities, body, token: token);
  }

  Future<http.Response> deleteActivity(String id, {String? token}) {
    return _apiService.delete(ApiConstants.activityById(id), token: token);
  }
}
