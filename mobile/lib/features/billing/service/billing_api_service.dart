import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Billing Management module. Builds
/// `/api/billing/**` requests on top of the shared [ApiService]. Response
/// decoding and domain mapping live in [BillingRepository].
class BillingApiService {
  final ApiService _apiService = ApiService();

  Future<http.Response> getBillingList({String? token}) {
    return _apiService.get(ApiConstants.billing, token: token);
  }

  Future<http.Response> updateBillingStatus(
    String moduleId,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(
      ApiConstants.billingByModuleId(moduleId),
      body,
      token: token,
    );
  }

  Future<http.Response> getBillingStatusChangeRequests({String? token}) {
    return _apiService.get(ApiConstants.billingStatusChangeRequests, token: token);
  }

  Future<http.Response> getBillingStatusChangeRequestById(String id, {String? token}) {
    return _apiService.get(ApiConstants.billingStatusChangeRequestById(id), token: token);
  }

  Future<http.Response> approveBillingStatusChangeRequest(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(
      ApiConstants.approveBillingStatusChangeRequest(id),
      body,
      token: token,
    );
  }

  Future<http.Response> rejectBillingStatusChangeRequest(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(
      ApiConstants.rejectBillingStatusChangeRequest(id),
      body,
      token: token,
    );
  }
}
