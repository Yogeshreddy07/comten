import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/di/dependency_injection.dart';
import 'core/services/push_notification_service.dart';
import 'features/activities/viewmodel/activity_view_model.dart';
import 'features/approvals/viewmodel/approval_view_model.dart';
import 'features/attendance/viewmodel/attendance_team_view_model.dart';
import 'features/attendance/viewmodel/attendance_view_model.dart';
import 'features/auth/viewmodel/auth_viewmodel.dart';
import 'features/billing/viewmodel/billing_approval_view_model.dart';
import 'features/billing/viewmodel/billing_view_model.dart';
import 'features/auth/view/splash_screen.dart';
import 'features/employees/viewmodel/employee_view_model.dart';
import 'features/modules/viewmodel/module_view_model.dart';
import 'features/notifications/viewmodel/notification_view_model.dart';
import 'features/projects/viewmodel/project_view_model.dart';
import 'features/settings/viewmodel/settings_view_model.dart';
import 'features/worklogs/viewmodel/work_log_approval_view_model.dart';
import 'features/worklogs/viewmodel/work_log_view_model.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_view_model.dart';
import 'core/utils/preference_util.dart';
import 'core/utils/secure_storage_service.dart';
import 'core/utils/snackbar_util.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PreferenceUtil.init();
  await Firebase.initializeApp();
  await PushNotificationService.instance.initialize();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(
            repository: DependencyInjection.authRepository,
            secureStorage: SecureStorageService(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProjectViewModel(
            repository: DependencyInjection.projectRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ModuleViewModel(
            repository: DependencyInjection.moduleRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => EmployeeViewModel(
            repository: DependencyInjection.employeeRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => WorkLogViewModel(
            repository: DependencyInjection.workLogRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => WorkLogApprovalViewModel(
            repository: DependencyInjection.workLogRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AttendanceViewModel(
            repository: DependencyInjection.attendanceRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AttendanceTeamViewModel(
            repository: DependencyInjection.attendanceRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => BillingViewModel(
            repository: DependencyInjection.billingRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => BillingApprovalViewModel(
            repository: DependencyInjection.billingRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ActivityViewModel(
            repository: DependencyInjection.activityRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ApprovalViewModel(
            repository: DependencyInjection.approvalRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationViewModel(
            repository: DependencyInjection.notificationRepository,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsViewModel(
            repository: DependencyInjection.authRepository,
          ),
        ),
        ChangeNotifierProvider(create: (_) => ThemeViewModel()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeViewModel = context.watch<ThemeViewModel>();

    return MaterialApp(
      title: 'Comten PMS',
      navigatorKey: PushNotificationService.instance.navigatorKey,
      navigatorObservers: [SnackbarDismissingObserver()],
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,

      darkTheme: AppTheme.darkTheme,

      themeMode: themeViewModel.themeMode,

      home: const SplashScreen(),
    );
  }
}