import '../../../shared/enums/approval_status.dart';

/// A Team Lead's Reason for Delay for one module - mirrors the backend's
/// `delay-requests` record (see `POST /api/notifications/delay-requests`).
/// While it is `PENDING` the same module can't be submitted again; a Captain
/// or Project Controller approves or rejects it.
class DelayRequest {
  final int id;
  final int moduleId;
  final String moduleName;
  final String projectName;
  final String reason;
  final String requestedByName;
  final String approvalStatus;
  final String? decidedByName;
  final String? decisionReason;

  const DelayRequest({
    required this.id,
    required this.moduleId,
    required this.moduleName,
    required this.projectName,
    required this.reason,
    required this.requestedByName,
    required this.approvalStatus,
    this.decidedByName,
    this.decisionReason,
  });

  ApprovalStatus get effectiveStatus =>
      ApprovalStatusX.fromApiValue(approvalStatus);

  factory DelayRequest.fromJson(Map<String, dynamic> json) {
    final decisionReason = json['decisionReason'] as String?;
    return DelayRequest(
      id: json['id'] as int,
      moduleId: json['moduleId'] as int,
      moduleName: json['moduleName'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      requestedByName: json['requestedByName'] as String? ?? '',
      approvalStatus: json['approvalStatus'] as String? ?? 'PENDING',
      decidedByName: json['decidedByName'] as String?,
      decisionReason:
          decisionReason == null || decisionReason.isEmpty ? null : decisionReason,
    );
  }
}
