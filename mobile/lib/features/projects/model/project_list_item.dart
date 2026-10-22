/// A single row of `GET /api/projects` - mirrors the backend's
/// `ProjectListItemResponse` exactly. Deliberately lighter than
/// [ProjectSummary]: just [moduleCount], not the full nested module list,
/// since the list only needs to render cards, not pre-fill a form.
class ProjectListItem {
  final int id;
  final String projectCode;
  final String projectName;
  final String? clientId;
  final bool isActive;
  final int moduleCount;

  /// Overall project status, computed server-side from its modules' statuses
  /// (or `INACTIVE` if the project itself is deactivated) - drives both the
  /// sort order and the status badge on [ProjectListScreen].
  final String status;

  const ProjectListItem({
    required this.id,
    required this.projectCode,
    required this.projectName,
    this.clientId,
    required this.isActive,
    required this.moduleCount,
    required this.status,
  });

  factory ProjectListItem.fromJson(Map<String, dynamic> json) {
    return ProjectListItem(
      id: json['id'] as int,
      projectCode: json['projectCode'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      clientId: json['clientId'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      moduleCount: json['moduleCount'] as int? ?? 0,
      status: json['status'] as String? ?? 'NOT_STARTED',
    );
  }

  ProjectListItem copyWith({bool? isActive, String? status}) {
    return ProjectListItem(
      id: id,
      projectCode: projectCode,
      projectName: projectName,
      clientId: clientId,
      isActive: isActive ?? this.isActive,
      moduleCount: moduleCount,
      status: status ?? this.status,
    );
  }
}
