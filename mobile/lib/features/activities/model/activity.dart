/// An activity as returned by the backend's `ActivityResponse`
/// (`GET/POST /api/activities`) - the master list a Project Controller
/// assigns into a project's Billable / Non-Billable configuration.
/// Equality is by [id] only, matching `ProjectMemberOption`, so
/// `List.contains`/toggle-based multi-select works against it.
class Activity {
  final int id;
  final String name;
  final bool active;

  const Activity({
    required this.id,
    required this.name,
    required this.active,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      active: json['active'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) => other is Activity && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
