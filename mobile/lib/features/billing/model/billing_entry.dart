import '../../../shared/enums/billing_stage.dart';

/// A module's current billing status - mirrors the backend's
/// `BillingResponse` exactly (see `GET /api/billing`,
/// `PUT /api/billing/{moduleId}`). Returned for every module in the
/// Billing work-stage, even ones with no billing record yet ([status] null
/// in that case).
class BillingEntry {
  final int moduleId;
  final String moduleName;

  /// The module's work status (e.g. IN_PROGRESS, COMPLETED) - distinct from
  /// [status]/[stage], which describe billing progress, not module work
  /// progress.
  final String? moduleStatus;

  final int projectId;
  final String projectCode;
  final String projectName;

  /// The module's Team Lead, fetched dynamically from the database (see
  /// `Module#teamLead` on the backend) - not editable here.
  final String? teamLeadName;

  final String? spocName;

  /// The granular status chosen on the Update Billing Status screen (see
  /// [BillingStatus]) - null when the project has no billing record yet.
  final String? status;

  /// Derived from [status] (see [BillingStageX.forStatus] /
  /// `com.comten.enums.BillingStage` on the backend), not chosen directly -
  /// null exactly when [status] is null.
  final String? stage;

  final String? remarks;

  final int? updatedById;
  final String? updatedByName;
  final DateTime? updatedAt;

  /// True when the last update attempted a Completed -> Pending reversion
  /// and was routed into a pending Captain-approval request instead of
  /// being applied directly - every other field above still reflects the
  /// record's unchanged, pre-request state in that case.
  final bool reversionPending;

  /// False when the module or its project is inactive - Billing Management
  /// is view-only in that case (see `UpdateBillingStatusScreen`).
  final bool editable;

  const BillingEntry({
    required this.moduleId,
    required this.moduleName,
    this.moduleStatus,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    this.teamLeadName,
    this.spocName,
    this.status,
    this.stage,
    this.remarks,
    this.updatedById,
    this.updatedByName,
    this.updatedAt,
    this.reversionPending = false,
    this.editable = true,
  });

  /// Whether a billing record exists yet for this project.
  bool get isSet => status != null;

  /// [stage] treated as [BillingStage.pending] when not yet set, so the
  /// Pending/Completed tabs on [BillingListScreen] can bucket every project.
  BillingStage get effectiveStage => !editable ? BillingStage.completed : BillingStageX.fromApiValue(stage);

  factory BillingEntry.fromJson(Map<String, dynamic> json) {
    return BillingEntry(
      moduleId: json['moduleId'] as int,
      moduleName: json['moduleName'] as String? ?? '',
      moduleStatus: json['editable'] == false ? 'INACTIVE' : json['moduleStatus'] as String?,
      projectId: json['projectId'] as int,
      projectCode: json['projectCode'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      teamLeadName: json['teamLeadName'] as String?,
      spocName: json['spocName'] as String?,
      status: json['status'] as String?,
      stage: json['stage'] as String?,
      remarks: json['remarks'] as String?,
      updatedById: json['updatedById'] as int?,
      updatedByName: json['updatedByName'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String).toLocal()
          : null,
      reversionPending: json['reversionPending'] as bool? ?? false,
      editable: json['editable'] as bool? ?? true,
    );
  }
}
