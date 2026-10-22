import '../../../shared/enums/approval_status.dart';

/// A Project Controller's request to change a module's End Date and/or
/// Estimated Hours - mirrors the backend's `ModuleChangeRequestResponse`
/// exactly (see `GET/POST /api/module-change-requests`). Independent of
/// the Team Lead's "Reason for Delay" notification - a PC can submit here
/// whether or not a delay was ever reported.
class ProjectChangeRequest {
  final int id;

  final int moduleId;
  final String moduleName;
  final int projectId;
  final String projectCode;
  final String projectName;

  final int requestedById;
  final String requestedByName;

  final DateTime? currentEndDate;
  final DateTime? proposedEndDate;
  final int? currentEstimatedHours;
  final int? proposedEstimatedHours;
  // Minute-precision siblings of the two fields above (e.g. 90 for "1h 30m") -
  // the backend derives these from the legacy hour fields for older requests,
  // so they're always populated whenever an hours change is proposed at all.
  final int? currentEstimatedMinutes;
  final int? proposedEstimatedMinutes;

  final String? remarks;
  final String status;
  final String? decisionReason;

  final int? decidedById;
  final String? decidedByName;
  final DateTime? decidedAt;

  final DateTime? createdAt;

  const ProjectChangeRequest({
    required this.id,
    required this.moduleId,
    required this.moduleName,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.requestedById,
    required this.requestedByName,
    this.currentEndDate,
    this.proposedEndDate,
    this.currentEstimatedHours,
    this.proposedEstimatedHours,
    this.currentEstimatedMinutes,
    this.proposedEstimatedMinutes,
    this.remarks,
    required this.status,
    this.decisionReason,
    this.decidedById,
    this.decidedByName,
    this.decidedAt,
    this.createdAt,
  });

  ApprovalStatus get effectiveStatus => ApprovalStatusX.fromApiValue(status);

  bool get changesEndDate => proposedEndDate != null;
  bool get changesEstimatedHours => proposedEstimatedMinutes != null;

  factory ProjectChangeRequest.fromJson(Map<String, dynamic> json) {
    return ProjectChangeRequest(
      id: json['id'] as int,
      moduleId: json['moduleId'] as int,
      moduleName: json['moduleName'] as String? ?? '',
      projectId: json['projectId'] as int,
      projectCode: json['projectCode'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      requestedById: json['requestedById'] as int,
      requestedByName: json['requestedByName'] as String? ?? '',
      currentEndDate: json['currentEndDate'] != null
          ? DateTime.parse(json['currentEndDate'] as String)
          : null,
      proposedEndDate: json['proposedEndDate'] != null
          ? DateTime.parse(json['proposedEndDate'] as String)
          : null,
      currentEstimatedHours: json['currentEstimatedHours'] as int?,
      proposedEstimatedHours: json['proposedEstimatedHours'] as int?,
      currentEstimatedMinutes: json['currentEstimatedMinutes'] as int?,
      proposedEstimatedMinutes: json['proposedEstimatedMinutes'] as int?,
      remarks: json['remarks'] as String?,
      status: json['status'] as String? ?? '',
      decisionReason: json['decisionReason'] as String?,
      decidedById: json['decidedById'] as int?,
      decidedByName: json['decidedByName'] as String?,
      decidedAt: json['decidedAt'] != null
          ? DateTime.parse(json['decidedAt'] as String).toLocal()
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String).toLocal()
          : null,
    );
  }
}
