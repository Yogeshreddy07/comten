/// Request body for `POST /api/notifications/delay-requests` - mirrors the
/// backend's `SubmitDelayRequestRequest` exactly.
class SubmitDelayRequest {
  final int moduleId;
  final String reason;

  const SubmitDelayRequest({
    required this.moduleId,
    required this.reason,
  });

  Map<String, dynamic> toJson() {
    return {
      'moduleId': moduleId,
      'reason': reason,
    };
  }
}
