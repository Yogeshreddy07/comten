import '../constants/app_strings.dart';

/// Staff hierarchy roles - values match the backend's `roles` table names
/// (see backend `DataSeeder`: CAPTAIN, PROJECT_CONTROLLER, TEAM_LEADER,
/// EMPLOYEE) via [UserRoleX.fromBackendValue], not the Dart identifiers
/// themselves.
enum UserRole {
  captain,
  projectManager,
  teamLeader,
  employee,
}

extension UserRoleX on UserRole {
  /// Maps the `role` string returned by every auth endpoint's
  /// `AuthResponse` (see backend `AuthMapper.toAuthResponse`) to a
  /// [UserRole]. Unknown or missing values fall back to [UserRole.employee]
  /// - the least-privileged dashboard - rather than guessing a higher-access
  /// role.
  static UserRole fromBackendValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'CAPTAIN':
        return UserRole.captain;
      case 'PROJECT_CONTROLLER':
        return UserRole.projectManager;
      case 'TEAM_LEADER':
        return UserRole.teamLeader;
      case 'EMPLOYEE':
        return UserRole.employee;
      default:
        return UserRole.employee;
    }
  }

  /// The inverse of [fromBackendValue] - the exact role string the backend
  /// expects as a request parameter (e.g. `GET /projects/users?role=`).
  String get backendValue {
    switch (this) {
      case UserRole.captain:
        return 'CAPTAIN';
      case UserRole.projectManager:
        return 'PROJECT_CONTROLLER';
      case UserRole.teamLeader:
        return 'TEAM_LEADER';
      case UserRole.employee:
        return 'EMPLOYEE';
    }
  }

  /// Human-readable label for role pickers (e.g. Team Member role selection).
  String get displayLabel {
    switch (this) {
      case UserRole.captain:
        return AppStrings.roleCaptain;
      case UserRole.projectManager:
        return AppStrings.roleProjectManager;
      case UserRole.teamLeader:
        return AppStrings.roleTeamLeader;
      case UserRole.employee:
        return AppStrings.roleEmployee;
    }
  }
}
