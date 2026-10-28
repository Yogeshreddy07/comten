import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import '../../../core/utils/preference_util.dart';
import '../../../core/utils/secure_storage_service.dart';
import '../../../shared/enums/user_role.dart';
import '../../auth/model/api_result.dart';
import '../model/create_employee_request.dart';
import '../model/employee.dart';
import '../model/employee_identity_validation.dart';
import '../model/update_employee_request.dart';
import '../service/employee_api_service.dart';

class EmployeeRepository {
  final EmployeeApiService _apiService = EmployeeApiService();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// The stored JWT for whichever employee is currently signed in - needed
  /// because `/api/employees/**` requires `Authentication` on the backend
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
    } on TimeoutException {
      return ApiResult(success: false, message: 'The server is taking too long. Check your connection and refresh before trying again.');
    } on FormatException {
      return ApiResult(success: false, message: 'The server returned an unexpected response. Please try again.');
    } catch (e) {
      return ApiResult(
        success: false,
        message: "Unable to connect to server.",
      );
    }
  }

  /// `GET /employees` - staff list, active and inactive. Pass [role] to
  /// scope the result to a single role (e.g. the Captain's Project
  /// Controller Management screen); omit it for the full staff directory.
  Future<ApiResult> getEmployees({UserRole? role}) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.getEmployees(token: token, role: role?.backendValue),
      isSuccess: (code) => code == 200,
      successMessage: "Employees loaded successfully",
      mapData: (data) => (data as List)
          .map((json) => Employee.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<ApiResult> validateIdentity({required String email, required String phone, int? excludeEmployeeId}) async {
    final token = await _currentToken();
    final body = <String, dynamic>{'email': email, 'phone': phone};
    if (excludeEmployeeId != null) body['excludeEmployeeId'] = excludeEmployeeId;
    return _request(
      () => _apiService.validateIdentity(body, token: token),
      isSuccess: (code) => code == 200,
      mapData: (data) => EmployeeIdentityValidation.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `POST /employees` - the backend generates a temp password and emails
  /// the new employee a welcome mail with their login credentials.
  Future<ApiResult> createEmployee(CreateEmployeeRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.createEmployee(request.toJson(), token: token),
      isSuccess: (code) => code == 200 || code == 201,
      mapData: (data) => Employee.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /employees/{id}`.
  Future<ApiResult> updateEmployee(int id, UpdateEmployeeRequest request) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.updateEmployee(id.toString(), request.toJson(), token: token),
      isSuccess: (code) => code == 200,
      mapData: (data) => Employee.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `DELETE /employees/{id}` - soft-deactivates the account (backend sets
  /// isActive=false; the row is never removed), not a hard delete.
  Future<ApiResult> deactivateEmployee(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.deactivateEmployee(id.toString(), token: token),
      isSuccess: (code) => code == 200 || code == 204,
      successMessage: "Employee deactivated successfully",
    );
  }

  /// `PUT /employees/{id}/activate` - reactivates a previously deactivated
  /// account (backend sets isActive=true).
  Future<ApiResult> activateEmployee(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.activateEmployee(id.toString(), token: token),
      isSuccess: (code) => code == 200,
      successMessage: "Employee activated successfully",
      mapData: (data) => Employee.fromJson(data as Map<String, dynamic>),
    );
  }

  /// `PUT /employees/{id}/delete` - soft-deletes the account (backend sets
  /// isDeleted=true and isActive=false; the row is retained for records but
  /// the employee never appears in the staff directory again).
  Future<ApiResult> deleteEmployee(int id) async {
    final token = await _currentToken();
    return _request(
      () => _apiService.deleteEmployee(id.toString(), token: token),
      isSuccess: (code) => code == 200 || code == 204,
      successMessage: "Employee deleted successfully",
    );
  }
}
