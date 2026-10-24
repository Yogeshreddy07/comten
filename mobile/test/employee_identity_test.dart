import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/employees/model/create_employee_request.dart';
import 'package:frontend/features/employees/model/employee.dart';
import 'package:frontend/shared/enums/user_role.dart';

void main() {
  test('new employee requests let the server allocate the code', () {
    const request = CreateEmployeeRequest(name: 'Test',
        phone: '9876543210', email: 'test@example.invalid', role: 'EMPLOYEE');
    expect(request.toJson().containsKey('employeeCode'), isFalse);
  });

  test('employee list sorts by numeric code across padding boundaries', () {
    Employee employee(String code) => Employee(id: 1, employeeCode: code,
        name: 'Test', phone: '', email: '', role: UserRole.employee, isActive: true);
    final employees = ['EMP1000', 'EMP999', 'EMP10', 'EMP002']
        .map(employee).toList()..sort(Employee.compareByCode);
    expect(employees.map((e) => e.employeeCode), ['EMP002', 'EMP10', 'EMP999', 'EMP1000']);
  });
}
