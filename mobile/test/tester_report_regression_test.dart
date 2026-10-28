import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/firebase_transport.dart';
import 'package:frontend/features/auth/model/api_result.dart';
import 'package:frontend/features/billing/model/billing_entry.dart';
import 'package:frontend/shared/enums/billing_stage.dart';
import 'package:frontend/features/employees/model/create_employee_request.dart';
import 'package:frontend/features/employees/model/update_employee_request.dart';
import 'package:frontend/features/employees/repository/employee_repository.dart';
import 'package:frontend/features/employees/viewmodel/employee_view_model.dart';
import 'package:frontend/features/modules/model/module_list_item.dart';
import 'package:frontend/features/modules/repository/module_repository.dart';
import 'package:frontend/features/notifications/repository/notification_repository.dart';
import 'package:frontend/features/projects/viewmodel/reason_for_delay_view_model.dart';

class FailingEmployees extends EmployeeRepository {
  @override
  Future<ApiResult> createEmployee(CreateEmployeeRequest request) async =>
      throw StateError('Synthetic failure');
  @override
  Future<ApiResult> updateEmployee(
    int id,
    UpdateEmployeeRequest request,
  ) async => throw StateError('Synthetic failure');
}

class DelayModules extends ModuleRepository {
  @override
  Future<ApiResult> getLedModules() async => ApiResult(
    success: true,
    message: '',
    data: [
      for (final value in [
        (1, 'IN_PROGRESS', null),
        (2, 'COMPLETED', null),
        (3, 'IN_PROGRESS', 'FULL_PAYMENT_RECEIVED'),
        (4, 'INACTIVE', null),
      ])
        ModuleListItem(
          id: value.$1,
          projectId: 1,
          projectCode: 'P',
          projectName: 'Project',
          moduleName: 'Module',
          status: value.$2,
          billingStatus: value.$3,
        ),
    ],
  );
}

void main() {
  test(
    'employee failures release loading state for the review screen',
    () async {
      final model = EmployeeViewModel(repository: FailingEmployees());
      final created = await model.createEmployee(
        CreateEmployeeRequest(
          name: 'Test',
          phone: '9000000001',
          email: 'test@example.invalid',
          role: 'EMPLOYEE',
        ),
      );
      expect(created.success, isFalse);
      expect(model.isSaving, isFalse);
      final updated = await model.updateEmployee(
        1,
        UpdateEmployeeRequest(
          name: 'Test',
          phone: '9000000001',
          email: 'test@example.invalid',
          role: 'EMPLOYEE',
        ),
      );
      expect(updated.success, isFalse);
      expect(model.isSaving, isFalse);
      model.dispose();
    },
  );
  test('delay picker excludes completed, paid and inactive modules', () async {
    final model = ReasonForDelayViewModel(
      moduleRepository: DelayModules(),
      notificationRepository: NotificationRepository(),
    );
    await model.fetchLedModules();
    expect(model.ledModules.map((m) => m.id), [1]);
    model.dispose();
  });
  test('inactive legacy billing row moves tabs without claiming payment', () {
    final row = BillingEntry.fromJson({
      'moduleId': 1,
      'projectId': 1,
      'editable': false,
      'stage': 'PENDING',
      'status': 'PART_PAYMENT_RECEIVED',
      'moduleStatus': 'IN_PROGRESS',
    });
    expect(row.effectiveStage, BillingStage.completed);
    expect(row.moduleStatus, 'INACTIVE');
    expect(row.status, 'PART_PAYMENT_RECEIVED');
  });
  test(
    'login throttling has recovery guidance; credentials are not called a connection failure',
    () {
      expect(
        FirebaseTransport.authErrorMessage('too-many-requests'),
        contains('Forgot Password'),
      );
      expect(
        FirebaseTransport.authErrorMessage('wrong-password'),
        contains('Incorrect employee code or password'),
      );
    },
  );
}
