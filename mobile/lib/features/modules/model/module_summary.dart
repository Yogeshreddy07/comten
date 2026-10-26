import '../../activities/model/activity.dart';

/// A module member as returned inside `ModuleResponse.members` - mirrors
/// the backend's `ModuleMemberResponse` (userId, employeeCode, name,
/// assignedAt). Carries the id so pickers (Team Leader / Employees) can
/// pre-select the right `ProjectMemberOption` once that role's list loads.
class ModuleSummaryMember {
  final int userId;
  final String employeeCode;
  final String name;

  const ModuleSummaryMember({
    required this.userId,
    required this.employeeCode,
    required this.name,
  });

  factory ModuleSummaryMember.fromJson(Map<String, dynamic> json) {
    return ModuleSummaryMember(
      userId: json['userId'] as int,
      employeeCode: json['employeeCode'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }
}

/// Full module detail - mirrors the backend's `ModuleResponse` (see
/// `POST /api/modules`, `GET /api/modules/{id}`). Used both for the
/// Create-module Success screen and the Module Details screen, since both
/// show the authoritative server state rather than raw form input.
class ModuleSummary {
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
  /// Approved Billable hours only - Non-Billable approved hours never count
  /// toward this (see backend `ModuleServiceImpl#syncCompletedHoursFromApprovedWorkLogs`).
  final int? completedHours;
  /// Same Billable-only total as [completedHours], computed server-side at
  /// read time (not stored) - use this over [completedHours] wherever the
  /// display should show minute precision (e.g. "1 hour 45 minutes")
  /// instead of the whole-hour-rounded value.
  final int? completedMinutes;
  final String status;
  final String? workStage;
  final List<ModuleSummaryMember> members;
  final List<Activity> billableActivities;
  final List<Activity> nonBillableActivities;
  final String? buildingClassification;
  final String? structureClassification;
  final int? numberOfFloors;
  /// In square feet.
  final double? area;

  const ModuleSummary({
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
    this.completedMinutes,
    required this.status,
    this.workStage,
    this.members = const [],
    this.billableActivities = const [],
    this.nonBillableActivities = const [],
    this.buildingClassification,
    this.structureClassification,
    this.numberOfFloors,
    this.area,
  });

  /// Display names of the team members, excluding the Team Leader (shown
  /// on its own row) even when the backend lists them as a member too.
  List<String> get memberNames => members
      .where((m) => m.userId != teamLeadId)
      .map((m) => m.name)
      .toList();

  ModuleSummary copyWith({String? status, String? workStage}) {
    return ModuleSummary(
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
      completedMinutes: completedMinutes,
      status: status ?? this.status,
      workStage: workStage ?? this.workStage,
      members: members,
      billableActivities: billableActivities,
      nonBillableActivities: nonBillableActivities,
      buildingClassification: buildingClassification,
      structureClassification: structureClassification,
      numberOfFloors: numberOfFloors,
      area: area,
    );
  }

  /// Working minutes remaining, clamped at 0 so an over-logged module (more
  /// completed than estimated) never displays as negative.
  int? get remainingMinutes {
    if (estimatedMinutes == null || completedMinutes == null) return null;
    final remaining = estimatedMinutes! - completedMinutes!;
    return remaining < 0 ? 0 : remaining;
  }

  factory ModuleSummary.fromJson(Map<String, dynamic> json) {
    final rawMembers = json['members'] as List<dynamic>? ?? const [];
    final rawBillableActivities =
        json['billableActivities'] as List<dynamic>? ?? const [];
    final rawNonBillableActivities =
        json['nonBillableActivities'] as List<dynamic>? ?? const [];
    return ModuleSummary(
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
      completedMinutes: json['completedMinutes'] as int?,
      status: json['status'] as String? ?? '',
      workStage: json['workStage'] as String?,
      members: rawMembers
          .map((m) => ModuleSummaryMember.fromJson(m as Map<String, dynamic>))
          .toList(),
      billableActivities: rawBillableActivities
          .map((a) => Activity.fromJson(a as Map<String, dynamic>))
          .toList(),
      nonBillableActivities: rawNonBillableActivities
          .map((a) => Activity.fromJson(a as Map<String, dynamic>))
          .toList(),
      buildingClassification: json['buildingClassification'] as String?,
      structureClassification: json['structureClassification'] as String?,
      numberOfFloors: json['numberOfFloors'] as int?,
      area: (json['area'] as num?)?.toDouble(),
    );
  }
}
