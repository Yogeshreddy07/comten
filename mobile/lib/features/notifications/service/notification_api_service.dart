import 'package:http/http.dart' as http;

import '../../../core/constant/api_constants.dart';
import '../../../core/network/api_service.dart';

/// Thin HTTP layer for the Notifications module. Builds
/// `/api/notifications/**` requests on top of the shared [ApiService].
/// Response decoding and domain mapping live in [NotificationRepository].
class NotificationApiService {
  final ApiService _apiService = ApiService();

  Future<http.Response> getNotifications({String? token}) {
    return _apiService.get(ApiConstants.notifications, token: token);
  }

  Future<http.Response> getUnreadCount({String? token}) {
    return _apiService.get(ApiConstants.notificationsUnreadCount, token: token);
  }

  Future<http.Response> markAsRead(String id, {String? token}) {
    return _apiService.put(ApiConstants.markNotificationRead(id), const {}, token: token);
  }

  Future<http.Response> submitDelayRequest(
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.post(ApiConstants.submitDelayRequest, body, token: token);
  }

  Future<http.Response> getDelayRequest(String id, {String? token}) {
    return _apiService.get(ApiConstants.delayRequestById(id), token: token);
  }

  Future<http.Response> approveDelayRequest(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(ApiConstants.approveDelayRequest(id), body, token: token);
  }

  Future<http.Response> rejectDelayRequest(
    String id,
    Map<String, dynamic> body, {
    String? token,
  }) {
    return _apiService.put(ApiConstants.rejectDelayRequest(id), body, token: token);
  }

  Future<http.Response> registerDeviceToken(String deviceToken, {String? token}) {
    return _apiService.post(
      ApiConstants.registerDeviceToken,
      {"token": deviceToken},
      token: token,
    );
  }

  Future<http.Response> unregisterDeviceToken(String deviceToken, {String? token}) {
    return _apiService.post(
      ApiConstants.unregisterDeviceToken,
      {"token": deviceToken},
      token: token,
    );
  }
}
