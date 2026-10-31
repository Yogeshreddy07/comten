// Run against owned local emulators with synthetic fixtures only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/services/firebase_environment.dart';
import 'package:frontend/core/theme/theme_view_model.dart';
import 'package:frontend/core/theme/app_colors.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import 'package:frontend/features/auth/repository/auth_repository.dart';
import 'package:frontend/features/auth/viewmodel/auth_viewmodel.dart';
import 'package:frontend/features/auth/view/activate_account_screen.dart';
import 'package:frontend/features/auth/view/activation_phone_screen.dart';
import 'package:frontend/features/modules/repository/module_repository.dart';
import 'package:frontend/features/modules/viewmodel/module_view_model.dart';
import 'package:frontend/features/modules/view/module_details_screen.dart';
import 'package:frontend/features/notifications/model/notification_item.dart';
import 'package:frontend/features/notifications/widgets/notification_card.dart';
import 'package:frontend/features/notifications/utils/notification_navigator.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('module notification and three-attempt OTP policy on Android', (tester) async {
    expect(FirebaseEnvironment.emulator, isTrue);
    await Firebase.initializeApp(options: FirebaseEnvironment.options);
    // A physical device reaches the host through adb reverse, not 10.0.2.2.
    await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099, automaticHostMapping: false);
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
    FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8086, automaticHostMapping: false);
    await Hive.initFlutter();
    final auth = AuthViewModel(repository: AuthRepository(), secureStorage: SecureStorageService());
    final modules = ModuleViewModel(repository: ModuleRepository());
    Widget wrap(Widget home) => MultiProvider(providers: [
      ChangeNotifierProvider<AuthViewModel>.value(value: auth),
      ChangeNotifierProvider<ModuleViewModel>.value(value: modules),
      ChangeNotifierProvider(create: (_) => ThemeViewModel()),
    ], child: MaterialApp(key: UniqueKey(), home: home));
    Future<void> tap(String text) async {
      final target = find.text(text).last;
      ScaffoldMessenger.of(tester.element(target)).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    }
    Future<void> enter(String label, String value) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(field).controller!.text, value);
    }
    await tester.pumpWidget(wrap(const ActivateAccountScreen()));
    await enter('Employee Code', 'DEVICEOTP001');
    await tap('Send OTP');
    for (final left in [2, 1]) {
      await enter('Email OTP', '000000');
      await tap('Verify OTP');
      expect(find.text('Incorrect OTP. $left attempt${left == 1 ? '' : 's'} left.'), findsOneWidget);
    }
    await enter('Email OTP', '123456');
    await tap('Verify OTP');
    await enter('New Password', 'SyntheticPass123!');
    await enter('Confirm Password', 'SyntheticPass123!');
    await tap('Continue');
    expect(find.byType(ActivationPhoneScreen), findsOneWidget);
    await tap('Send Phone OTP');
    for (final left in [2, 1, 0]) {
      await enter('Phone OTP', '000000');
      await tap('Verify Phone OTP');
      expect(find.text(left > 0 ? 'Incorrect OTP. $left attempt${left == 1 ? '' : 's'} left.'
          : 'No attempts left. Please try again after 15 minutes.'), findsOneWidget);
    }
    expect(find.textContaining('Resend OTP in'), findsOneWidget);
    final blocked = await auth.sendActivationPhoneOtp();
    expect(blocked.success, isFalse);
    expect(blocked.data['retryAfterSeconds'], greaterThan(800));

    await tester.pumpWidget(wrap(const ActivateAccountScreen(key: ValueKey('email-lock'))));
    await enter('Employee Code', 'DEVICEOTP002');
    await tap('Send OTP');
    for (var i = 0; i < 3; i++) {
      await enter('Email OTP', '000000');
      await tap('Verify OTP');
    }
    expect(find.text('No attempts left. Please try again after 15 minutes.'), findsOneWidget);
    expect(find.textContaining('Resend OTP in'), findsOneWidget);
    final resend = await AuthRepository().sendActivationOtp('DEVICEOTP002');
    expect(resend.success, isFalse);
    expect(resend.data['retryAfterSeconds'], greaterThan(800));

    await FirebaseAuth.instance.signInWithEmailAndPassword(email: 'emp001@accounts.crompton.invalid', password: 'SyntheticPass123!');
    final fixture = (await FirebaseFirestore.instance.doc('device-test-fixtures/current').get()).data()!;
    final note = NotificationItem.fromJson(Map<String, dynamic>.from(fixture['notification']));
    await tester.pumpWidget(wrap(Scaffold(body: Builder(builder: (context) => NotificationCard(
      notification: note,
      onTap: () => NotificationNavigator.openFor(context: context, type: note.effectiveType,
          moduleId: note.moduleId, projectId: note.projectId),
    )))));
    await tester.pumpAndSettle();
    expect(find.text('30%'), findsOneWidget);
    expect(tester.widget<Text>(find.text('30%')).style!.color, AppColors.statusActive);
    await tap('Module 30% completed');
    expect(find.byType(ModuleDetailsScreen), findsOneWidget);
    expect(tester.widget<ModuleDetailsScreen>(find.byType(ModuleDetailsScreen)).moduleId, note.moduleId);
    expect(find.text('Device module'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
    modules.dispose();
  });
}
