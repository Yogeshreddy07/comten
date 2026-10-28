import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend/core/theme/theme_view_model.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import 'package:frontend/features/auth/repository/auth_repository.dart';
import 'package:frontend/features/auth/view/splash_screen.dart';
import 'package:frontend/features/auth/view/welcome_screen.dart';
import 'package:frontend/features/auth/viewmodel/auth_viewmodel.dart';

class StartupAuth extends AuthViewModel {
  StartupAuth()
    : super(
        repository: AuthRepository(),
        secureStorage: SecureStorageService(),
      );
  @override
  Future<void> checkBiometricSupport() async {}
  @override
  Future<String?> getActiveEmployeeCode() async => null;
}

void main() {
  testWidgets('Ready signed-out startup has no artificial splash wait', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>(create: (_) => StartupAuth()),
          ChangeNotifierProvider<ThemeViewModel>(
            create: (_) => ThemeViewModel(),
          ),
        ],
        child: const MaterialApp(home: SplashScreen()),
      ),
    );
    var elapsed = 0;
    while (find.byType(WelcomeScreen).evaluate().isEmpty && elapsed < 3000) {
      await tester.pump(const Duration(milliseconds: 16));
      elapsed += 16;
    }
    // Logical Flutter frame time isolates the route gate, not native startup.
    debugPrint('startup_route_ready_ms=$elapsed');
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(elapsed, lessThan(100));
    await tester.pumpAndSettle();
  });
}
