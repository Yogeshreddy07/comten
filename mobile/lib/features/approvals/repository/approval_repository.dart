import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../auth/model/api_result.dart';
import '../model/project_change_request.dart';
import '../model/project_deactivation_request.dart';
import '../model/submit_change_request.dart';
import '../service/approval_api_service.dart';

class ApprovalRepository {
  final ApprovalApiService _apiService = ApprovalApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  Future<String?> _currentToken() async {
    final employeeCode = await _secureStorage.getActiveEmployeeCode();
    if (employeeCode == null || employeeCode.isEmpty) return null;
    return PreferenceUtil.getJwtToken(employeeCode);
  }

  /// Shared request-and-decode path - same contract as
  /// `BillingRepository._request`/`ProjectRepository._request`.
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

  /// `GET /module-change-requests` - every request (Captain's Approval queue).
  Future<ApiResult> getChangeRequests() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getChangeRequests(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Change requests loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => ProjectChangeRequest.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `GET /module-change-requests/{id}` - used to deep-link from a
  /// notification tap, which only carries the request's id.
  Future<ApiResult> getChangeRequestDetails(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getChangeRequestById(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Change request loaded successfully",
      mapData: (data) => ProjectChangeRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `GET /module-change-requests?moduleId=` - used by Edit Module to
  /// check for an existing pending request before allowing another submit.
  Future<ApiResult> getChangeRequestsForModule(int moduleId) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getChangeRequestsForModule(moduleId.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Change requests loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => ProjectChangeRequest.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `POST /module-change-requests`.
  Future<ApiResult> submitChangeRequest(SubmitChangeRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.submitChangeRequest(request.toJson(), token: token),
      isSuccess: (code) => code == 200 || code == 201,
      mapData: (data) => ProjectChangeRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /module-change-requests/{id}/approve`.
  Future<ApiResult> approve(int id, String reason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.approve(id.toString(), {'reason': reason}, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Change request approved successfully",
      mapData: (data) => ProjectChangeRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /module-change-requests/{id}/reject`.
  Future<ApiResult> reject(int id, String reason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.reject(id.toString(), {'reason': reason}, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Change request rejected successfully",
      mapData: (data) => ProjectChangeRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `GET /project-deactivation-requests` - Captain's Approval queue.
  Future<ApiResult> getDeactivationRequests() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getDeactivationRequests(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Deactivation requests loaded successfully",
      mapData: (data) => (data as List)
          .map((json) =>
              ProjectDeactivationRequest.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `PUT /project-deactivation-requests/{id}/approve`.
  Future<ApiResult> approveDeactivation(int id, String reason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.approveDeactivation(id.toString(), {'reason': reason}, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Deactivation request approved successfully",
      mapData: (data) =>
          ProjectDeactivationRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /project-deactivation-requests/{id}/reject`.
  Future<ApiResult> rejectDeactivation(int id, String reason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.rejectDeactivation(id.toString(), {'reason': reason}, token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Deactivation request rejected successfully",
      mapData: (data) =>
          ProjectDeactivationRequest.fromJson(data as Map<String, dynamic>),
    );
  }
}
