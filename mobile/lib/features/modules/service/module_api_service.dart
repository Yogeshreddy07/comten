import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Modules module.
/// Builds module endpoint requests on top of the shared [ApiService].
/// Response decoding and domain mapping live in [ModuleRepository].
/// Every method requires a [token]: `/api/modules/**` is behind
/// `.anyRequest().authenticated()` in the backend's `SecurityConfig`.
class ModuleApiService {
  final ApiService _apiService = ApiService();

  Future<http.Response> getModules({String? token, int? projectId}) {
    final query = projectId != null ? '?projectId=$projectId' : '';
    return _apiService.get('${ApiConstants.modules}$query', token: token);
  }

  Future<http.Response> getModuleById(String id, {String? token}) {
    return _apiService.get(ApiConstants.moduleById(id), token: token);
  }

  Future<http.Response> createModule(
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.post(ApiConstants.modules, body, token: token);
  }

  Future<http.Response> updateModule(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(ApiConstants.moduleById(id), body, token: token);
  }

  Future<http.Response> deactivateModule(String id, {String? token}) {
    return _apiService.delete(ApiConstants.moduleById(id), token: token);
  }

  Future<http.Response> activateModule(String id, {String? token}) {
    return _apiService.put(ApiConstants.activateModule(id), const {}, token: token);
  }

  Future<http.Response> deleteModule(String id, {String? token}) {
    return _apiService.put(ApiConstants.deleteModule(id), const {}, token: token);
  }

  Future<http.Response> getLedModules({String? token}) {
    return _apiService.get(ApiConstants.modulesLed, token: token);
  }

  Future<http.Response> getCompletedLedModules({String? token}) {
    return _apiService.get(ApiConstants.modulesLedCompleted, token: token);
  }

  Future<http.Response> updateWorkStage(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(ApiConstants.moduleWorkStage(id), body, token: token);
  }
}
