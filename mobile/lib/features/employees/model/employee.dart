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
  final String? temporaryPassword;

  const Employee({
    required this.id,
    required this.employeeCode,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.isActive,
    this.isDeleted = false,
    this.temporaryPassword,
  });

  String get phoneLocal =>
      phone.startsWith('+91') ? phone.substring(3) : phone;

  static int compareByCode(Employee a, Employee b) {
    final pattern = RegExp(r'^(.*?)(\d+)$');
    final left = pattern.firstMatch(a.employeeCode.toUpperCase());
    final right = pattern.firstMatch(b.employeeCode.toUpperCase());
    if (left != null && right != null && left[1] == right[1]) {
      final order = BigInt.parse(left[2]!).compareTo(BigInt.parse(right[2]!));
      if (order != 0) return order;
    }
    return a.employeeCode.toUpperCase().compareTo(b.employeeCode.toUpperCase());
  }

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
      temporaryPassword: json['temporaryPassword'] as String?,
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
