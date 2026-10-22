import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../auth/model/api_result.dart';
import '../model/create_module_request.dart';
import '../model/module_list_item.dart';
import '../model/module_summary.dart';
import '../model/update_module_request.dart';
import '../service/module_api_service.dart';

class ModuleRepository {
  final ModuleApiService _apiService = ModuleApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// The stored JWT for whichever employee is currently signed in - needed
  /// because `/api/modules/**` requires `Authentication` on the backend
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

  /// `GET /modules?projectId=` - module rows for [ProjectDetailsScreen]'s
  /// module list, or every accessible module when [projectId] is omitted.
  Future<ApiResult> getModules({int? projectId}) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getModules(token: token, projectId: projectId),
      isSuccess: (code) => code == 200,
      successMessage: "Modules loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => ModuleListItem.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `GET /modules/{id}` - full detail for [ModuleDetailsScreen] and as the
  /// pre-fill source for [EditModuleScreen].
  Future<ApiResult> getModuleDetails(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getModuleById(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Module details loaded successfully",
      mapData: (data) => ModuleSummary.fromJson(data as Map<String, dynamic>),
    );
  }

  /// Adds a module to an existing project (`POST /modules`).
  Future<ApiResult> createModule(CreateModuleRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.createModule(request.toJson(), token: token),
      isSuccess: (code) => code == 200 || code == 201,
      mapData: (data) => ModuleSummary.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /modules/{id}` - used by [EditModuleScreen].
  Future<ApiResult> updateModule(int id, UpdateModuleRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.updateModule(id.toString(), request.toJson(), token: token),
      isSuccess: (code) => code == 200,
      mapData: (data) => ModuleSummary.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `DELETE /modules/{id}` - soft-deactivates the module.
  Future<ApiResult> deactivateModule(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.deactivateModule(id.toString(), token: token),
      isSuccess: (code) => code == 200 || code == 204,
      successMessage: "Module deactivated successfully",
    );
  }

  /// `PUT /modules/{id}/activate` - reactivates a previously deactivated
  /// module, restoring the status it had before deactivation.
  Future<ApiResult> activateModule(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.activateModule(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Module activated successfully",
    );
  }

  /// `PUT /modules/{id}/delete` - soft-deletes the module (backend sets
  /// `isDeleted` to true; the row is retained for records but never appears
  /// in any future list response).
  Future<ApiResult> deleteModule(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.deleteModule(id.toString(), token: token),
      isSuccess: (code) => code == 200 || code == 204,
      successMessage: "Module deleted successfully",
    );
  }

  /// `GET /modules/led` - active modules the current Team Lead leads, for
  /// the Reason for Delay screen's module picker.
  Future<ApiResult> getLedModules() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getLedModules(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Modules loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => ModuleListItem.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `GET /modules/led/completed` - Completed modules the current Team Lead
  /// leads, for the Status Update screen's module picker (only a Completed
  /// module is eligible to move into the Billing work stage).
  Future<ApiResult> getCompletedLedModules() async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getCompletedLedModules(token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Modules loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => ModuleListItem.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `PUT /modules/{id}/work-stage` - Team Lead-only WIP/Billing toggle.
  Future<ApiResult> updateWorkStage(int moduleId, String workStage) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.updateWorkStage(
        moduleId.toString(),
        {'workStage': workStage},
        token: token,
      ),
      isSuccess: (code) => code == 200,
      successMessage: "Module work stage updated successfully",
    );
  }
}
