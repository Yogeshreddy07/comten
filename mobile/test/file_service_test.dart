import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:frontend/core/network/api_service.dart';
import 'package:frontend/core/services/file_service.dart';

class SyntheticApi extends ApiService {
  final calls = <String>[];
  bool rejectCompletion = false;
  http.Response reply(dynamic data, [int status = 200]) => http.Response(jsonEncode({'success':status==200,'data':data,'message':'Synthetic result'}), status);
  @override
  Future<http.Response> get(String endpoint, {String? token}) async {
    calls.add('GET $endpoint');
    if (endpoint.endsWith('/download')) return reply({'url':'https://synthetic.r2.invalid/download','headers':{'If-Match':'synthetic-etag'}});
    return reply([{'id':'synthetic-id','name':'synthetic.pdf'}]);
  }
  @override
  Future<http.Response> post(String endpoint, Map<String,dynamic> body, {String? token, Duration? timeout}) async {
    calls.add('POST $endpoint');
    if (endpoint.endsWith('/complete')) return reply({}, rejectCompletion ? 422 : 200);
    return reply({'id':'synthetic-id','url':'https://synthetic.r2.invalid/upload','headers':{'Content-Type':'application/pdf','If-None-Match':'*'}});
  }
  @override
  Future<http.Response> delete(String endpoint, {String? token}) async { calls.add('DELETE $endpoint');return reply(null); }
}

void main() {
  test('signed PUT and GET never carry Firebase bearer credentials', () async {
    final api = SyntheticApi(), dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request, handler) {
      requests.add(request);
      handler.resolve(Response(requestOptions: request, statusCode: 200, data: request.method == 'GET' ? <int>[37,80,68,70] : null));
    }));
    final service = FileService(api: api, objects: dio);
    await service.upload('employee_document',4,'synthetic.pdf','application/pdf',Uint8List.fromList([37,80,68,70]),(_, _) {});
    expect(requests.single.headers['If-None-Match'], '*');
    expect(requests.single.headers.containsKey('Authorization'),false);
    expect(api.calls.last,'POST /files/synthetic-id/complete');
    expect(await service.download('synthetic-id'),[37,80,68,70]);
    expect(requests.last.headers['If-Match'],'synthetic-etag');
    expect(requests.last.headers.containsKey('Authorization'),false);
  });

  test('ambiguous upload confirms once without retransmitting bytes', () async {
    final api = SyntheticApi(), dio = Dio();var sends = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler) {
      sends++;handler.reject(DioException(requestOptions: request, type: DioExceptionType.receiveTimeout));
    }));
    await FileService(api: api,objects: dio).upload('employee_document',4,'synthetic.pdf','application/pdf',Uint8List.fromList([1]),(_, _) {});
    expect(sends,1);expect(api.calls.where((call)=>call.endsWith('/complete')).length,1);
    expect(api.calls.any((call)=>call.startsWith('DELETE')),false);
  });

  test('failed confirmation cancels upload for server cleanup', () async {
    final api = SyntheticApi()..rejectCompletion = true, dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)=>handler.resolve(Response(requestOptions:request,statusCode:200))));
    await expectLater(FileService(api:api,objects:dio).upload('employee_document',4,'synthetic.pdf','application/pdf',Uint8List.fromList([1]),(_, _) {}),throwsException);
    expect(api.calls.last,'DELETE /files/synthetic-id');
  });

  test('oversized and empty files fail before requesting any capability', () async {
    final api = SyntheticApi();
    final service = FileService(api:api);
    for (final bytes in [Uint8List(0),Uint8List(10*1024*1024+1)]) {
      await expectLater(service.upload('employee_document',4,'synthetic.pdf','application/pdf',bytes,(_, _) {}),throwsException);
    }
    expect(api.calls,isEmpty);
  });
}
