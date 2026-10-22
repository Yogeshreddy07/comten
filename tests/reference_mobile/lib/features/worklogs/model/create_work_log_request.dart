/// Request body for `POST /api/work-logs` - mirrors the backend's
/// `CreateWorkLogRequest` exactly.
class CreateWorkLogRequest {
  final int moduleId;
  final DateTime workDate;
  final int? billableDurationSeconds;
  final int? nonBillableDurationSeconds;
  final String workDone;
  final List<int> billableActivityIds;
  final List<int> nonBillableActivityIds;

  const CreateWorkLogRequest({
    required this.moduleId,
    required this.workDate,
    this.billableDurationSeconds,
    this.nonBillableDurationSeconds,
    required this.workDone,
    this.billableActivityIds = const [],
    this.nonBillableActivityIds = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'moduleId': moduleId,
      'workDate': _formatDate(workDate),
      'billableDurationSeconds': billableDurationSeconds,
      'nonBillableDurationSeconds': nonBillableDurationSeconds,
      'workDone': workDone,
      'billableActivityIds': billableActivityIds,
      'nonBillableActivityIds': nonBillableActivityIds,
    };
  }

  static String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
