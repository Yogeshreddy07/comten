import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Employee Management module.
/// Builds employee endpoint requests on top of the shared [ApiService].
/// Response decoding and domain mapping live in [EmployeeRepository].
/// Every method requires a [token]: `/api/employees/**` is behind
/// `.anyRequest().authenticated()` in the backend's `SecurityConfig`.
class EmployeeApiService {
  final ApiService _apiService = ApiService();

  Future<http.Response> validateIdentity(Map<String, dynamic> body, {String? token}) {
    return _apiService.post('/employees/validate-identity', body, token: token);
  }

  /// The general management directory contains Employees and Team Leaders.
  /// An explicit role preserves the separate Project Controller directory.
  Future<http.Response> getEmployees({String? token, String? role}) {
    if (role == null) {
      return _apiService.get('${ApiConstants.employees}?staffOnly=true', token: token);
    }
    final query = Uri(queryParameters: {'role': role}).query;
    return _apiService.get('${ApiConstants.employees}?$query', token: token);
  }

  Future<http.Response> createEmployee(
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.post(ApiConstants.employees, body, token: token);
  }

  Future<http.Response> updateEmployee(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(ApiConstants.employeeById(id), body, token: token);
  }

  Future<http.Response> deactivateEmployee(String id, {String? token}) {
    return _apiService.delete(ApiConstants.employeeById(id), token: token);
  }

  Future<http.Response> activateEmployee(String id, {String? token}) {
    return _apiService.put(ApiConstants.activateEmployee(id), const {}, token: token);
  }

  Future<http.Response> deleteEmployee(String id, {String? token}) {
    return _apiService.put(ApiConstants.deleteEmployee(id), const {}, token: token);
  }
}
