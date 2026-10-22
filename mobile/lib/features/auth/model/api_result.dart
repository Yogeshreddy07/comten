class ApiResult {
  final bool success;
  final String message;
  final dynamic data;

  ApiResult({
    required this.success,
    required this.message,
    this.data,
  });
}