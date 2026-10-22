import '../../activities/model/activity.dart';

/// A single timesheet entry - mirrors the backend's `WorkLogResponse`
/// exactly (see `GET /api/work-logs/my`, `GET /api/work-logs`,
/// `POST /api/work-logs`).
class WorkLog {
  final int id;

  final int moduleId;
  final String moduleName;
  final int projectId;
  final String projectCode;
  final String projectName;

  final int employeeId;
  final String employeeCode;
  final String employeeName;

  final DateTime workDate;
  final int? billableDurationSeconds;
  final int? nonBillableDurationSeconds;
  final String workDone;
  final List<Activity> billableActivities;
  final List<Activity> nonBillableActivities;

  final String approvalStatus;
  final String? rejectionReason;

  final int? approvedById;
  final String? approvedByName;
  final DateTime? approvedAt;

  final DateTime? createdAt;

  const WorkLog({
    required this.id,
    required this.moduleId,
    required this.moduleName,
    required this.projectId,
    required this.projectCode,
    required this.projectName,
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.workDate,
    this.billableDurationSeconds,
    this.nonBillableDurationSeconds,
    required this.workDone,
    this.billableActivities = const [],
    this.nonBillableActivities = const [],
    required this.approvalStatus,
    this.rejectionReason,
    this.approvedById,
    this.approvedByName,
    this.approvedAt,
    this.createdAt,
  });

  factory WorkLog.fromJson(Map<String, dynamic> json) {
    final rawBillableActivities =
        json['billableActivities'] as List<dynamic>? ?? const [];
    final rawNonBillableActivities =
        json['nonBillableActivities'] as List<dynamic>? ?? const [];
    return WorkLog(
      id: json['id'] as int,
      moduleId: json['moduleId'] as int,
      moduleName: json['moduleName'] as String? ?? '',
      projectId: json['projectId'] as int,
      projectCode: json['projectCode'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      employeeId: json['employeeId'] as int,
      employeeCode: json['employeeCode'] as String? ?? '',
      employeeName: json['employeeName'] as String? ?? '',
      workDate: DateTime.parse(json['workDate'] as String),
      billableDurationSeconds: json['billableDurationSeconds'] as int?,
      nonBillableDurationSeconds: json['nonBillableDurationSeconds'] as int?,
      workDone: json['workDone'] as String? ?? '',
      billableActivities: rawBillableActivities
          .map((a) => Activity.fromJson(a as Map<String, dynamic>))
          .toList(),
      nonBillableActivities: rawNonBillableActivities
          .map((a) => Activity.fromJson(a as Map<String, dynamic>))
          .toList(),
      approvalStatus: json['approvalStatus'] as String? ?? '',
      rejectionReason: json['rejectionReason'] as String?,
      approvedById: json['approvedById'] as int?,
      approvedByName: json['approvedByName'] as String?,
      approvedAt: json['approvedAt'] != null
          ? DateTime.parse(json['approvedAt'] as String).toLocal()
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String).toLocal()
          : null,
    );
  }

  WorkLog copyWith({
    String? approvalStatus,
    String? rejectionReason,
    String? approvedByName,
    DateTime? approvedAt,
  }) {
    return WorkLog(
      id: id,
      moduleId: moduleId,
      moduleName: moduleName,
      projectId: projectId,
      projectCode: projectCode,
      projectName: projectName,
      employeeId: employeeId,
      employeeCode: employeeCode,
      employeeName: employeeName,
      workDate: workDate,
      billableDurationSeconds: billableDurationSeconds,
      nonBillableDurationSeconds: nonBillableDurationSeconds,
      workDone: workDone,
      billableActivities: billableActivities,
      nonBillableActivities: nonBillableActivities,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      approvedById: approvedById,
      approvedByName: approvedByName ?? this.approvedByName,
      approvedAt: approvedAt ?? this.approvedAt,
      createdAt: createdAt,
    );
  }
}
