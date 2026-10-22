/// The current user's account/security state - mirrors the backend's
/// `UserSettingsResponse` exactly (see `GET /api/users/me`).
class UserSettings {
  final int userId;
  final String employeeCode;
  final String name;
  final String email;
  final String? phone;
  final String role;

  final bool phoneVerified;

  const UserSettings({
    required this.userId,
    required this.employeeCode,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    required this.phoneVerified,
  });

  factory UserSettings.fromJson(Map<String, dynamic> json) {
    return UserSettings(
      userId: json['userId'] as int,
      employeeCode: json['employeeCode'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? '',
      phoneVerified: json['phoneVerified'] as bool? ?? false,
    );
  }
}
