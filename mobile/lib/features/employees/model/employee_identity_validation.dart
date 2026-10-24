class EmployeeIdentityValidation {
  final Map<String, String> errors;

  const EmployeeIdentityValidation(this.errors);

  bool get valid => errors.isEmpty;

  factory EmployeeIdentityValidation.fromJson(Map<String, dynamic> json) {
    if (json['valid'] is! bool || json['errors'] is! Map) {
      throw const FormatException('Invalid employee validation response');
    }
    final errors = Map<String, String>.from(json['errors'] as Map);
    if (json['valid'] != errors.isEmpty) {
      throw const FormatException('Inconsistent employee validation response');
    }
    return EmployeeIdentityValidation(errors);
  }
}
