/// Request body for `POST /api/module-change-requests` - mirrors the
/// backend's `SubmitModuleChangeRequest` exactly.
class SubmitChangeRequest {
  final int moduleId;
  final DateTime? proposedEndDate;
  /// Total minutes (e.g. 90 for "1h 30m") - null means this request doesn't
  /// propose an hours change.
  final int? proposedEstimatedMinutes;
  final String? remarks;

  const SubmitChangeRequest({
    required this.moduleId,
    this.proposedEndDate,
    this.proposedEstimatedMinutes,
    this.remarks,
  });

  static String _isoDate(DateTime date) => date.toIso8601String().substring(0, 10);

  Map<String, dynamic> toJson() {
    return {
      'moduleId': moduleId,
      if (proposedEndDate != null) 'proposedEndDate': _isoDate(proposedEndDate!),
      if (proposedEstimatedMinutes != null) 'proposedEstimatedMinutes': proposedEstimatedMinutes,
      if (remarks != null && remarks!.isNotEmpty) 'remarks': remarks,
    };
  }
}
