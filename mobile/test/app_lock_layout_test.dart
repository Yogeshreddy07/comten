import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/core/theme/theme_view_model.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import 'package:frontend/features/auth/repository/auth_repository.dart';
import 'package:frontend/features/auth/view/app_lock_screen.dart';
import 'package:frontend/features/auth/viewmodel/auth_viewmodel.dart';

class LockAuthFixture extends AuthViewModel {
  LockAuthFixture()
    : super(
        repository: AuthRepository(),
        secureStorage: SecureStorageService(),
      );
  @override
  Future<void> checkBiometricSupport() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final size in [const Size(360, 800), const Size(760, 360)]) {
    testWidgets('App lock keypad remains reachable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthViewModel>(
              create: (_) => LockAuthFixture(),
            ),
            ChangeNotifierProvider<ThemeViewModel>(
              create: (_) => ThemeViewModel(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const AppLockScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final zero = find.widgetWithText(OutlinedButton, '0');
      await tester.ensureVisible(zero);
      await tester.pumpAndSettle();
      expect(zero.hitTestable(), findsOneWidget);
    });
  }
}
