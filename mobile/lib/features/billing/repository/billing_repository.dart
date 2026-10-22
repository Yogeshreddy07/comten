import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../auth/model/api_result.dart';
import '../model/billing_entry.dart';
import '../model/billing_status_change_request.dart';
import '../model/update_billing_status_request.dart';
import '../service/billing_api_service.dart';

class BillingRepository {
  final BillingApiService _apiService = BillingApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// The stored JWT for whichever employee is currently signed in - needed
  /// because `/api/billing/**` requires `Authentication` on the backend
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

  /// `GET /billing` - every project with its current billing status (see
  /// [BillingListScreen]'s All Projects / Pending / Completed tabs).
  Future<ApiResult> getBillingList() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getBillingList(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Billing status list loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => BillingEntry.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `PUT /billing/{moduleId}`.
  Future<ApiResult> updateBillingStatus(
    int moduleId,
    UpdateBillingStatusRequest request,
  ) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.updateBillingStatus(
        moduleId.toString(),
        request.toJson(),
        token: token,
      ),
      isSuccess: (code) => code == 200,
      successMessage: "Billing status updated successfully",
      mapData: (data) => BillingEntry.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `GET /billing-status-change-requests` - every request (Captain's
  /// Billing Approvals queue).
  Future<ApiResult> getBillingStatusChangeRequests() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getBillingStatusChangeRequests(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Billing status change requests loaded successfully",
      mapData: (data) => (data as List)
          .map((json) =>
              BillingStatusChangeRequest.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `GET /billing-status-change-requests/{id}` - used to deep-link from a
  /// notification tap, which only carries the request's id.
  Future<ApiResult> getChangeRequestDetails(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getBillingStatusChangeRequestById(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Billing status change request loaded successfully",
      mapData: (data) =>
          BillingStatusChangeRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /billing-status-change-requests/{id}/approve`.
  Future<ApiResult> approveBillingStatusChangeRequest(int id, String reason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.approveBillingStatusChangeRequest(
        id.toString(),
        {'reason': reason},
        token: token,
      ),
      isSuccess: (code) => code == 200,
      successMessage: "Billing status change request approved successfully",
      mapData: (data) =>
          BillingStatusChangeRequest.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /billing-status-change-requests/{id}/reject`.
  Future<ApiResult> rejectBillingStatusChangeRequest(int id, String reason) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.rejectBillingStatusChangeRequest(
        id.toString(),
        {'reason': reason},
        token: token,
      ),
      isSuccess: (code) => code == 200,
      successMessage: "Billing status change request rejected successfully",
      mapData: (data) =>
          BillingStatusChangeRequest.fromJson(data as Map<String, dynamic>),
    );
  }
}
