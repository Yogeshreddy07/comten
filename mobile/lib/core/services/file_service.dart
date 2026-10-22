import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../network/api_service.dart';

/// Permanent credentials and file authorization stay in FastAPI. Signed object
/// requests deliberately use a separate client with no Firebase bearer token.
class FileService {
  final ApiService _api;
  final Dio _objects;
  FileService({ApiService? api, Dio? objects})
      : _api = api ?? ApiService(),
        _objects = objects ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 30), sendTimeout: const Duration(seconds: 60)));

  dynamic _decode(dynamic response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300 || body['success'] != true) {
      throw Exception(body['message'] ?? body['detail'] ?? 'File operation failed');
    }
    return body['data'];
  }

  Future<List<Map<String, dynamic>>> list(String category, int targetId) async {
    final result = <Map<String, dynamic>>[];
    String? cursor;
    do {
      final page = (_decode(await _api.get('/files?category=$category&targetId=$targetId&limit=100${cursor == null ? '' : '&after=$cursor'}')) as List).cast<Map<String, dynamic>>();
      result.addAll(page);
      cursor = page.length == 100 ? page.last['id'] as String : null;
    } while (cursor != null);
    return result;
  }

  Future<void> upload(String category, int targetId, String name, String type, Uint8List bytes, void Function(int, int) progress) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) throw Exception('Choose a file up to 10 MB');
    final grant = _decode(await _api.post('/files/authorize-upload', {'category': category, 'targetId': targetId, 'name': name, 'contentType': type, 'size': bytes.length})) as Map<String, dynamic>;
    final id = grant['id'] as String;
    try {
      await _objects.put<void>(grant['url'] as String, data: bytes,
          options: Options(headers: Map<String, dynamic>.from(grant['headers'] as Map), contentType: type, followRedirects: false), onSendProgress: progress);
    } on DioException {
      // PUT may have succeeded before the connection was lost. Confirm before
      // offering a fresh upload; never blindly repeat a single-use capability.
      try { _decode(await _api.post('/files/$id/complete', {})); return; } catch (_) { /* surface a safe, retryable message below */ }
      try { await _api.delete('/files/$id'); } catch (_) { /* abandoned uploads are reclaimed by the server job */ }
      throw Exception('Upload could not be confirmed. Check your connection and try again.');
    }
    try { _decode(await _api.post('/files/$id/complete', {})); }
    catch (_) {
      try { await _api.delete('/files/$id'); } catch (_) { /* server cleanup owns the remaining capability */ }
      rethrow;
    }
  }

  Future<Uint8List> download(String id) async {
    final grant = _decode(await _api.get('/files/$id/download')) as Map<String, dynamic>;
    try {
      final response = await _objects.get<List<int>>(grant['url'] as String,
          options: Options(responseType: ResponseType.bytes, headers: Map<String, dynamic>.from(grant['headers'] as Map), followRedirects: false));
      return Uint8List.fromList(response.data!);
    } on DioException { throw Exception('Download failed. Try again to obtain a fresh download link.'); }
  }

  Future<void> delete(String id) async { _decode(await _api.delete('/files/$id')); }
}
