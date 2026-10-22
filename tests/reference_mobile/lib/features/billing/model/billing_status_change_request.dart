import '../../../shared/enums/approval_status.dart';

/// A Project Controller's request to revert a project's billing status from
/// Completed back to Pending - mirrors the backend's
/// `BillingStatusChangeRequestResponse` exactly (see
/// `GET/PUT /api/billing-status-change-requests/**`). Created automatically
/// by `PUT /api/billing/{projectId}` when that specific transition is
/// attempted - there is no direct "submit" action on this model.
class BillingStatusChangeRequest {
  final int id;

  final int moduleId;
  final String moduleName;
  final int projectId;
  final String projectCode;
  final String projectName;

  final int requestedById;
  final String requestedByName;

  final String currentStatus;
  final String proposedStatus;
  final String? proposedSpocName;

  final String? remarks;
  final String status;
  final String? decisionReason;

  final int? decidedById;
  final String? decidedByName;
  final DateTime? decidedAt;

  final DateTime? createdAt;

  const BillingStatusChangeRequest({
    required this.id,
    required this.moduleId,
    required this.moduleName,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.requestedById,
    required this.requestedByName,
    required this.currentStatus,
    required this.proposedStatus,
    this.proposedSpocName,
    this.remarks,
    required this.status,
    this.decisionReason,
    this.decidedById,
    this.decidedByName,
    this.decidedAt,
    this.createdAt,
  });

  ApprovalStatus get effectiveStatus => ApprovalStatusX.fromApiValue(status);

  factory BillingStatusChangeRequest.fromJson(Map<String, dynamic> json) {
    return BillingStatusChangeRequest(
      id: json['id'] as int,
      moduleId: json['moduleId'] as int,
      moduleName: json['moduleName'] as String? ?? '',
      projectId: json['projectId'] as int,
      projectCode: json['projectCode'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      requestedById: json['requestedById'] as int,
      requestedByName: json['requestedByName'] as String? ?? '',
      currentStatus: json['currentStatus'] as String? ?? '',
      proposedStatus: json['proposedStatus'] as String? ?? '',
      proposedSpocName: json['proposedSpocName'] as String?,
      remarks: json['remarks'] as String?,
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
