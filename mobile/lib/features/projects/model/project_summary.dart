import '../../modules/model/module_list_item.dart';
import '../../modules/model/module_summary.dart';

/// Full project detail - mirrors the backend's `ProjectResponse` (see
/// `POST /api/projects`, `GET /api/projects/{id}`). A project itself only
/// carries identity/client info now; its modules (Team Lead, team, timeline,
/// hours, status) are nested in [modules].
class ProjectSummary {
  final int id;
  final String projectCode;
  final String projectName;
  final String? clientId;
  final bool isActive;

  /// Overall project status, computed server-side from its modules' statuses
  /// (or `INACTIVE` if the project itself is deactivated).
  final String status;

  /// Derived server-side from the project's active modules (earliest start,
  /// latest end, summed hours) - deactivated modules are excluded, so these
  /// shift when a module is deactivated.
  final DateTime? startDate;
  final DateTime? endDate;
  final int? estimatedMinutes;

  /// Total hours utilized - approved Billable minutes summed across the same
  /// modules as [estimatedMinutes], computed server-side at read time.
  final int? workedMinutes;

  /// Pending hours - [estimatedMinutes] minus [workedMinutes], floored at 0
  /// server-side. Null when no module carries an estimate.
  final int? pendingMinutes;

  final List<ModuleListItem> modules;
  /// Creation responses already include full module details for the success view.
  final List<ModuleSummary> moduleDetails;

  const ProjectSummary({
    required this.id,
    required this.projectCode,
    required this.projectName,
    this.clientId,
    required this.isActive,
    required this.status,
    this.startDate,
    this.endDate,
    this.estimatedMinutes,
    this.workedMinutes,
    this.pendingMinutes,
    this.modules = const [],
    this.moduleDetails = const [],
  });

  factory ProjectSummary.fromJson(Map<String, dynamic> json) {
    final rawModules = json['modules'] as List<dynamic>? ?? const [];
    return ProjectSummary(
      id: json['id'] as int,
      projectCode: json['projectCode'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      clientId: json['clientId'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      status: json['status'] as String? ?? 'NOT_STARTED',
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'] as String)
          : null,
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'] as String)
          : null,
      estimatedMinutes: json['estimatedMinutes'] as int?,
      workedMinutes: (json['workedMinutes'] as num?)?.toInt(),
      pendingMinutes: (json['pendingMinutes'] as num?)?.toInt(),
      modules: rawModules
          .map((m) => ModuleListItem.fromJson(m as Map<String, dynamic>))
          .toList(),
      moduleDetails: rawModules.where((m) => (m as Map).containsKey('members'))
          .map((m) => ModuleSummary.fromJson(m as Map<String, dynamic>)).toList(),
    );
  }
}
