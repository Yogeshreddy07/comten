import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Projects module.
/// Builds project endpoint requests on top of the shared [ApiService].
/// Response decoding and domain mapping live in [ProjectRepository].
/// Every method requires a [token]: `/api/projects/**` is behind
/// `.anyRequest().authenticated()` in the backend's `SecurityConfig`.
class ProjectApiService {
  final ApiService _apiService = ApiService();

  Future<http.Response> getProjects({
    String? token,
    bool? active,
    bool? hasInProgressModule,
  }) {
    final queryParams = <String, String>{
      if (active != null) 'active': active.toString(),
      if (hasInProgressModule != null)
        'hasInProgressModule': hasInProgressModule.toString(),
    };
    if (queryParams.isEmpty) {
      return _apiService.get(ApiConstants.projects, token: token);
    }
    final query = Uri(queryParameters: queryParams).query;
    return _apiService.get('${ApiConstants.projects}?$query', token: token);
  }

  Future<http.Response> getProjectById(String id, {String? token}) {
    return _apiService.get(ApiConstants.projectById(id), token: token);
  }

  /// Creates a project together with its first module.
  Future<http.Response> createProject(
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.post(ApiConstants.projects, body, token: token);
  }

  Future<http.Response> updateProject(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(ApiConstants.projectById(id), body, token: token);
  }

  Future<http.Response> deactivateProject(String id, {String? token}) {
    return _apiService.delete(ApiConstants.projectById(id), token: token);
  }

  Future<http.Response> activateProject(String id, {String? token}) {
    return _apiService.put(ApiConstants.activateProject(id), const {}, token: token);
  }

  Future<http.Response> deleteProject(String id, {String? token}) {
    return _apiService.put(ApiConstants.deleteProject(id), const {}, token: token);
  }

  Future<http.Response> getUsersByRole(String role, {String? token}) {
    final query = Uri(queryParameters: {'role': role}).query;
    return _apiService.get('${ApiConstants.projectUsers}?$query', token: token);
  }
}
