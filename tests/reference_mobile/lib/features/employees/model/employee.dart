import '../../../shared/enums/user_role.dart';

/// A staff member as returned by the backend's `EmployeeResponse`
/// (`GET/POST/PUT /api/employees`). [phone] arrives with the +91 country
/// code the backend prepends on create/update; [phoneLocal] strips it back
/// off for pre-filling the 10-digit Mobile Number form field.
class Employee {
  final int id;
  final String employeeCode;
  final String name;
  final String phone;
  final String email;
  final UserRole role;
  final bool isActive;
  final bool isDeleted;

  const Employee({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.isActive,
    this.isDeleted = false,
  });

  String get phoneLocal =>
      phone.startsWith('+91') ? phone.substring(3) : phone;

  factory Employee.fromJson(Map<String, dynamic> json) {
    return Employee(
      id: json['id'] as int,
      employeeCode: json['employeeCode'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: UserRoleX.fromBackendValue(json['role'] as String?),
      isActive: json['isActive'] as bool? ?? true,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  Employee copyWith({bool? isActive, bool? isDeleted}) {
    return Employee(
      id: id,
      employeeCode: employeeCode,
      name: name,
      phone: phone,
      email: email,
      role: role,
      isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
