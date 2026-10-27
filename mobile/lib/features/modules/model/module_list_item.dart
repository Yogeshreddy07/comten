/// A single row of `GET /api/modules` - mirrors the backend's
/// `ModuleListItemResponse` exactly. Deliberately lighter than
/// [ModuleSummary]: no members/team-lead-id, since the list only needs to
/// render cards, not pre-fill the Edit form.
class ModuleListItem {
  final int id;
  final int projectId;
  final String projectCode;
  final String projectName;
  final String moduleName;
  final int? teamLeadId;
  final String? teamLeadName;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? estimatedMinutes;
  final int? completedHours;
  final String status;

  /// The status as stored, before [status] is shown as Completed for a module
  /// with no pending hours left - what timesheet eligibility and the WIP
  /// guard go by.
  final String? storedStatus;

  String get lifecycleStatus => storedStatus ?? status;

  /// Team Lead-controlled WIP/Billing toggle (see `ProjectWorkStage`) -
  /// distinct from [status], the module lifecycle status.
  final String? workStage;

  /// Billing Management status (e.g. FULL_PAYMENT_RECEIVED once Completed).
  final String? billingStatus;

  const ModuleListItem({
    required this.id,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.moduleName,
    this.teamLeadId,
    this.teamLeadName,
    this.startDate,
    this.endDate,
    this.estimatedMinutes,
    this.completedHours,
    required this.status,
    this.storedStatus,
    this.workStage,
    this.billingStatus,
  });

  factory ModuleListItem.fromJson(Map<String, dynamic> json) {
    return ModuleListItem(
      id: json['id'] as int,
      projectId: json['projectId'] as int,
      projectCode: json['projectCode'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      moduleName: json['moduleName'] as String? ?? '',
      teamLeadId: json['teamLeadId'] as int?,
      teamLeadName: json['teamLeadName'] as String?,
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'] as String)
          : null,
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'] as String)
          : null,
      estimatedMinutes: json['estimatedMinutes'] as int?,
      completedHours: json['completedHours'] as int?,
      status: json['status'] as String? ?? '',
      storedStatus: json['storedStatus'] as String?,
      workStage: json['workStage'] as String?,
      billingStatus: json['billingStatus'] as String?,
    );
  }

  ModuleListItem copyWith({String? status, String? workStage}) {
    return ModuleListItem(
      id: id,
      projectId: projectId,
      projectCode: projectCode,
      projectName: projectName,
      moduleName: moduleName,
      teamLeadId: teamLeadId,
      teamLeadName: teamLeadName,
      startDate: startDate,
      endDate: endDate,
      estimatedMinutes: estimatedMinutes,
      completedHours: completedHours,
      status: status ?? this.status,
      storedStatus: status ?? storedStatus,
      workStage: workStage ?? this.workStage,
      billingStatus: billingStatus,
    );
  }
}
