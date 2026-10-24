/// Request payload for `POST /api/employees` - mirrors the backend's
/// `CreateEmployeeRequest` field-for-field. The backend allocates the next
/// employee code when omitted and normalizes Indian phone numbers to +91.
class CreateEmployeeRequest {
  final String employeeCode;
  final String name;
  final String phone;
  final String email;
  final String role;

  const CreateEmployeeRequest({
    this.employeeCode = '',
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
  });

  Map<String, dynamic> toJson() {
    return {
      if (employeeCode.isNotEmpty) 'employeeCode': employeeCode,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
    };
  }
}
