import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/network/firebase_transport.dart';
import 'package:frontend/core/theme/theme_view_model.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import 'package:frontend/core/utils/uppercase_text_input_formatter.dart';
import 'package:frontend/features/auth/model/api_result.dart';
import 'package:frontend/features/auth/repository/auth_repository.dart';
import 'package:frontend/features/auth/view/login_screen.dart';
import 'package:frontend/features/auth/viewmodel/auth_viewmodel.dart';

class LoginModel extends AuthViewModel {
  LoginModel()
    : super(
        repository: AuthRepository(),
        secureStorage: SecureStorageService(),
      );
  String? submittedCode;
  String? submittedPassword;
  @override
  Future<void> checkBiometricSupport() async {}
  @override
  Future<ApiResult> login({
    required String employeeCode,
    required String password,
  }) async {
    submittedCode = employeeCode;
    submittedPassword = password;
    return ApiResult(success: false, message: 'Synthetic login response');
  }
}

void main() {
  test(
    'formatting pasted and edited employee codes preserves cursor position',
    () {
      const formatter = UppercaseTextInputFormatter();
      const edit = TextEditingValue(
        text: 'pC012',
        selection: TextSelection.collapsed(offset: 2),
      );
      final result = formatter.formatEditUpdate(TextEditingValue.empty, edit);
      expect(result.text, 'PC012');
      expect(result.selection, edit.selection);
      expect(FirebaseTransport.isUppercaseLoginIdentifier('EMP012'), isTrue);
      expect(FirebaseTransport.isUppercaseLoginIdentifier('emp012'), isFalse);
      expect(FirebaseTransport.isUppercaseLoginIdentifier('eMp012'), isFalse);
    },
  );

  testWidgets('login displays uppercase codes and preserves password case', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final model = LoginModel();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>.value(value: model),
          ChangeNotifierProvider(create: (_) => ThemeViewModel()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    final code = find.widgetWithText(TextFormField, 'Employee Code');
    for (final input in ['emp012', 'pC023', 'tL003']) {
      await tester.enterText(code, input);
      expect(
        tester.widget<TextFormField>(code).controller!.text,
        input.toUpperCase(),
      );
    }
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'MixedCase123!',
    );
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();
    expect(model.submittedCode, 'TL003');
    expect(model.submittedPassword, 'MixedCase123!');
    await tester.pumpWidget(const SizedBox());
    model.dispose();
  });
}
