/// Request payload for `POST /api/employees` - mirrors the backend's
/// `CreateEmployeeRequest` field-for-field. [phone] must be the bare
/// 10-digit number; the backend prepends +91 itself.
class CreateEmployeeRequest {
  final String employeeCode;
  final String name;
  final String phone;
  final String email;
  final String role;

  const CreateEmployeeRequest({
    required this.employeeCode,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
  });

  Map<String, dynamic> toJson() {
    return {
      'employeeCode': employeeCode,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
    };
  }
}
