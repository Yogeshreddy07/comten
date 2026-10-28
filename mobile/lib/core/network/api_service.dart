import '../services/performance_trace.dart';
import 'firebase_transport.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../shared/constants/app_strings.dart';
import '../constant/api_constants.dart';
import '../services/session_manager.dart';
import '../services/account_cache.dart';

class ApiService {
  Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) => PerformanceTrace.measure(
    'api.post',
    () => _post(endpoint, body, token: token, timeout: timeout),
  );
  Future<http.Response> get(String endpoint, {String? token}) =>
      PerformanceTrace.measure('api.get', () => _get(endpoint, token: token));
  Future<http.Response> put(
    String endpoint,
    Map<String, dynamic> body, {
    String? token,
  }) => PerformanceTrace.measure(
    'api.put',
    () => _put(endpoint, body, token: token),
  );
  Future<http.Response> delete(String endpoint, {String? token}) =>
      PerformanceTrace.measure(
        'api.delete',
        () => _delete(endpoint, token: token),
      );
  static final _firebase = FirebaseTransport();
  static final http.Client _client = PerformanceHttpClient(http.Client());
  static String get baseUrl => ApiConstants.baseUrl;

  static const _timeout = Duration(seconds: ApiConstants.requestTimeoutSeconds);

  Map<String, String> _buildHeaders(String? token) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Every call below routes its response through here before returning it,
  /// so this is the single place that needs to recognize a superseded
  /// session (see `JwtFilter.SESSION_INVALIDATED_MESSAGE` on the backend) -
  /// no individual repository needs to know about it. Deliberately
  /// fire-and-forget: the caller still gets its normal (failed) response and
  /// decodes it as usual, while [SessionManager] independently clears local
  /// auth data and navigates to the login screen.
  http.Response _checkSession(http.Response response) {
    if (response.statusCode == 401 && response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final message = decoded['message'];
          // Both mean "this token is no longer usable" and both must bounce to
          // login - they differ only in what the user is told (superseded by
          // another device vs. session simply ended).
          if (message == AppStrings.sessionInvalidatedMessage) {
            SessionManager.instance.handleSessionInvalidated(
              AppStrings.sessionInvalidatedDisplayMessage,
            );
          } else if (message == AppStrings.sessionEndedMessage) {
            SessionManager.instance.handleSessionInvalidated(
              AppStrings.sessionEndedMessage,
            );
          }
        }
      } catch (_) {
        // Not a JSON body - nothing to check.
      }
    }
    return response;
  }

  Future<http.Response> _post(
    String endpoint,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async {
    final direct = await PerformanceTrace.measure(
      'firebase.transport',
      () => _firebase.request('POST', endpoint, body),
    );
    if (direct != null) return direct;
    token = await PerformanceTrace.measure(
      'auth.token',
      () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    );
    final response = await _client
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: _buildHeaders(token),
          body: jsonEncode(body),
        )
        .timeout(timeout ?? _timeout);
    if (response.statusCode < 300) await AccountCache.instance.invalidateData();
    return _checkSession(response);
  }

  Future<http.Response> _get(String endpoint, {String? token}) async {
    final direct = await PerformanceTrace.measure(
      'firebase.transport',
      () => _firebase.request('GET', endpoint, const {}),
    );
    if (direct != null) return direct;
    token = await PerformanceTrace.measure(
      'auth.token',
      () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    );
    final response = await _getWithRetry(endpoint, token);
    return _checkSession(response);
  }

  /// One silent retry on connection failure/timeout - covers a backend that
  /// was still waking up (e.g. Render's free-tier spin-down after being
  /// idle) and hadn't finished booting by the first attempt, which every
  /// dashboard module's initial fetch was hitting at once right after the
  /// app reopened, each surfacing its own "Unable to connect to server."
  /// Retrying is safe here specifically because GET is read-only - it can
  /// never duplicate a write, unlike POST/PUT/DELETE, which deliberately
  /// don't get this treatment. Mirrors the same "one retry covers a
  /// transient just-woke-up failure" approach `AuthRepository.sendOtp`
  /// already uses for the SMS gateway.
  Future<http.Response> _getWithRetry(String endpoint, String? token) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = _buildHeaders(token);
    try {
      return await _client.get(uri, headers: headers).timeout(_timeout);
    } catch (_) {
      return await _client.get(uri, headers: headers).timeout(_timeout);
    }
  }

  Future<http.Response> _put(
    String endpoint,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final direct = await PerformanceTrace.measure(
      'firebase.transport',
      () => _firebase.request('PUT', endpoint, body),
    );
    if (direct != null) return direct;
    token = await PerformanceTrace.measure(
      'auth.token',
      () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    );
    final response = await _client
        .put(
          Uri.parse('$baseUrl$endpoint'),
          headers: _buildHeaders(token),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    return _checkSession(response);
  }

  Future<http.Response> _delete(String endpoint, {String? token}) async {
    final direct = await PerformanceTrace.measure(
      'firebase.transport',
      () => _firebase.request('DELETE', endpoint, const {}),
    );
    if (direct != null) return direct;
    token = await PerformanceTrace.measure(
      'auth.token',
      () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    );
    final response = await _client
        .delete(Uri.parse('$baseUrl$endpoint'), headers: _buildHeaders(token))
        .timeout(_timeout);
    if (response.statusCode < 300) await AccountCache.instance.invalidateData();
    return _checkSession(response);
  }
}
