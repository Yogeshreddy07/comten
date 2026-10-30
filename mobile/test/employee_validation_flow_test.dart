import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import 'package:frontend/features/auth/model/api_result.dart';
import 'package:frontend/features/auth/repository/auth_repository.dart';
import 'package:frontend/features/auth/viewmodel/auth_viewmodel.dart';
import 'package:frontend/features/employees/model/employee_identity_validation.dart';
import 'package:frontend/features/employees/repository/employee_repository.dart';
import 'package:frontend/features/employees/view/add_edit_employee_screen.dart';
import 'package:frontend/features/employees/view/review_employee_screen.dart';
import 'package:frontend/features/employees/viewmodel/employee_view_model.dart';
import 'package:frontend/shared/enums/user_role.dart';
import 'package:frontend/shared/widgets/app_button.dart';

const conflict =
    'Phone number is already in use by Existing Employee (EMP001).';
ApiResult validation([Map<String, String> errors = const {}]) => ApiResult(
  success: true,
  message: 'Success',
  data: EmployeeIdentityValidation(Map<String, String>.of(errors)),
);

class FakeEmployeeRepository extends EmployeeRepository {
  int validationCalls = 0;
  ApiResult result = validation({'phone': conflict});
  @override
  Future<ApiResult> validateIdentity({
    required String email,
    required String phone,
    int? excludeEmployeeId,
  }) async {
    validationCalls++;
    return result;
  }
}

class FakeAuth extends AuthViewModel {
  FakeAuth()
    : super(
        repository: AuthRepository(),
        secureStorage: SecureStorageService(),
      );
  @override
  Future<void> checkBiometricSupport() async {}
  @override
  UserRole get role => UserRole.captain;
}

AppButton confirmButton(WidgetTester tester) => tester.widget<AppButton>(
  find.byWidgetPredicate(
    (widget) => widget is AppButton && widget.text == 'Confirm',
  ),
);

Future<void> review(
  WidgetTester tester,
  Future<ApiResult> Function() validate,
  Future<ApiResult> Function() save,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EmployeeViewModel(repository: FakeEmployeeRepository()),
      child: MaterialApp(
        home: ReviewEmployeeScreen(
          isEditMode: false,
          name: 'Test',
          role: UserRole.employee,
          employeeCode: 'Assigned automatically on save',
          phone: '9876543210',
          email: 'test@example.com',
          onValidateIdentity: validate,
          onConfirmSave: save,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'review is ready and Confirm opens the dialog without validation',
    (tester) async {
      var validations = 0;
      var saves = 0;
      final pending = Completer<ApiResult>();
      await review(
        tester,
        () {
          validations++;
          return pending.future;
        },
        () async {
          saves++;
          return ApiResult(success: true, message: 'Saved');
        },
      );
      expect(confirmButton(tester).isLoading, isFalse);
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(validations, 0);
      await tester.ensureVisible(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(validations, 0);
      expect(saves, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(confirmButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'Save sends one write immediately and keeps Confirm text during saving',
    (tester) async {
      var validations = 0;
      var saves = 0;
      final pending = Completer<ApiResult>();
      await review(
        tester,
        () async {
          validations++;
          return validation();
        },
        () {
          saves++;
          return pending.future;
        },
      );
      await tester.ensureVisible(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(saves, 1);
      expect(validations, 0);
      expect(confirmButton(tester).isLoading, isFalse);
      expect(confirmButton(tester).onPressed, isNull);
      expect(find.text('Saving employee...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      pending.complete(ApiResult(success: true, message: 'Saved'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('server rejects a new duplicate and review shows its owner', (
    tester,
  ) async {
    var validations = 0;
    await review(tester, () async {
      validations++;
      return validation({'phone': conflict});
    }, () async => ApiResult(success: false, message: conflict));
    await tester.ensureVisible(find.text('Confirm'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(validations, 1);
    expect(find.text(conflict), findsWidgets);
    expect(confirmButton(tester).isLoading, isFalse);
    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets(
    'failed save and validation allow retry without a stuck spinner',
    (tester) async {
      var validations = 0;
      await review(
        tester,
        () async => ++validations == 1
            ? ApiResult(success: false, message: 'Connection unavailable')
            : validation(),
        () async => ApiResult(success: false, message: 'Save failed'),
      );
      await tester.ensureVisible(find.text('Confirm'));
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Connection unavailable'), findsOneWidget);
      expect(confirmButton(tester).isLoading, isFalse);
      expect(confirmButton(tester).onPressed, isNull);
      await tester.ensureVisible(find.text('Retry validation'));
      await tester.tap(find.text('Retry validation'));
      await tester.pumpAndSettle();
      expect(confirmButton(tester).onPressed, isNotNull);
    },
  );

  testWidgets(
    'form shows duplicate beside contact and only proceeds after correction',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeEmployeeRepository();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => EmployeeViewModel(repository: repository),
            ),
            ChangeNotifierProvider<AuthViewModel>(create: (_) => FakeAuth()),
          ],
          child: const MaterialApp(
            home: AddEditEmployeeScreen(fixedRole: UserRole.employee),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'New Employee',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mobile Number'),
        '9876543210',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email ID'),
        'new@example.com',
      );
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewEmployeeScreen), findsNothing);
      expect(find.text(conflict), findsOneWidget);
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, 'Next'))
            .onPressed,
        isNull,
      );
      repository.result = validation();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mobile Number'),
        '9876543211',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewEmployeeScreen), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(confirmButton(tester).isLoading, isFalse);
      expect(repository.validationCalls, 2);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewEmployeeScreen), findsNothing);
      expect(find.text('New Employee'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email ID'),
        'changed@example.com',
      );
      await tester.ensureVisible(find.text('Next'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(repository.validationCalls, 3);
      expect(find.text('changed@example.com'), findsOneWidget);
      expect(confirmButton(tester).isLoading, isFalse);
      expect(confirmButton(tester).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}
