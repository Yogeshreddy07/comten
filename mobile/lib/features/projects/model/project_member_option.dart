import '../../../shared/enums/user_role.dart';

/// A selectable user for Team Leader / Team Members pickers. Mirrors the
/// backend's `UserSummaryResponse` (see `GET /api/projects/users?role=`)
/// exactly - id, employeeCode, name, email, role.
class ProjectMemberOption {
  final int id;
  final String employeeCode;
  final String name;
  final String email;
  final UserRole role;

  const ProjectMemberOption({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.email,
    required this.role,
  });

  factory ProjectMemberOption.fromJson(Map<String, dynamic> json) {
    return ProjectMemberOption(
      id: json['id'] as int,
      employeeCode: json['employeeCode'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: UserRoleX.fromBackendValue(json['role'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectMemberOption && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
