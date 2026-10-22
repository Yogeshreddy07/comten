/// Request payload for `PUT /api/employees/{id}` - mirrors the backend's
/// `UpdateEmployeeRequest`. Every field is optional: the backend only
/// overwrites a field when its key is present in the JSON body, so omit a
/// field to leave it unchanged. Employee code is immutable server-side and
/// deliberately absent here.
class UpdateEmployeeRequest {
  final String? name;
  final String? phone;
  final String? email;
  final String? role;

  const UpdateEmployeeRequest({
    this.name,
    this.phone,
    this.email,
    this.role,
  });

  Map<String, dynamic> toJson() {
    return {
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (role != null) 'role': role,
    };
  }
}
