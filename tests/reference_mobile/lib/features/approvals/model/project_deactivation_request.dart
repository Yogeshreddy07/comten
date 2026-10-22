import '../../../shared/enums/approval_status.dart';

/// A Project Controller's request to deactivate a project that has already
/// moved into Billing Management - mirrors the backend's
/// `ProjectDeactivationRequestResponse` exactly (see
/// `GET /api/project-deactivation-requests`). Created automatically when the
/// PC taps Deactivate on such a project; a Captain approves (project becomes
/// Inactive, its billing entries read as Completed) or rejects (nothing
/// changes).
class ProjectDeactivationRequest {
  final int id;

  final int projectId;
  final String projectCode;
  final String projectName;

  final int requestedById;
  final String requestedByName;

  final String status;
  final String? decisionReason;

  final int? decidedById;
  final String? decidedByName;
  final DateTime? decidedAt;

  final DateTime? createdAt;

  const ProjectDeactivationRequest({
    required this.id,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.requestedById,
    required this.requestedByName,
    required this.status,
    this.decisionReason,
    this.decidedById,
    this.decidedByName,
    this.decidedAt,
    this.createdAt,
  });

  ApprovalStatus get effectiveStatus => ApprovalStatusX.fromApiValue(status);

  factory ProjectDeactivationRequest.fromJson(Map<String, dynamic> json) {
    return ProjectDeactivationRequest(
      id: json['id'] as int,
      projectId: json['projectId'] as int,
      projectCode: json['projectCode'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      requestedById: json['requestedById'] as int,
      requestedByName: json['requestedByName'] as String? ?? '',
      status: json['status'] as String? ?? '',
      decisionReason: json['decisionReason'] as String?,
      decidedById: json['decidedById'] as int?,
      decidedByName: json['decidedByName'] as String?,
      decidedAt: json['decidedAt'] != null
          ? DateTime.parse(json['decidedAt'] as String)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }
}
