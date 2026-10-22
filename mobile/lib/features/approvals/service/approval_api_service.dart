import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Approval module (`/api/module-change-requests/**`).
/// Response decoding and domain mapping live in [ApprovalRepository].
class ApprovalApiService {
  final ApiService _apiService = ApiService();

  Future<http.Response> getChangeRequests({String? token}) {
    return _apiService.get(ApiConstants.moduleChangeRequests, token: token);
  }

  Future<http.Response> getChangeRequestById(String id, {String? token}) {
    return _apiService.get(ApiConstants.moduleChangeRequestById(id), token: token);
  }

  Future<http.Response> getChangeRequestsForModule(String moduleId, {String? token}) {
    return _apiService.get(
      ApiConstants.moduleChangeRequestsByModule(moduleId),
      token: token,
    );
  }

  Future<http.Response> submitChangeRequest(
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.post(ApiConstants.moduleChangeRequests, body, token: token);
  }

  Future<http.Response> approve(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(ApiConstants.approveModuleChangeRequest(id), body, token: token);
  }

  Future<http.Response> reject(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(ApiConstants.rejectModuleChangeRequest(id), body, token: token);
  }

  // ---- Project deactivation requests (`/api/project-deactivation-requests/**`) ----

  Future<http.Response> getDeactivationRequests({String? token}) {
    return _apiService.get(ApiConstants.projectDeactivationRequests, token: token);
  }

  Future<http.Response> approveDeactivation(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(
      ApiConstants.approveProjectDeactivationRequest(id),
      body,
      token: token,
    );
  }

  Future<http.Response> rejectDeactivation(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(
      ApiConstants.rejectProjectDeactivationRequest(id),
      body,
      token: token,
    );
  }
}
