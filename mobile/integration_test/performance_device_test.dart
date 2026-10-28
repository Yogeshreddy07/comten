// Finite physical-device probe against disposable local fixtures only.
// The sandbox package does not replace or sign out the installed cloud app.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/main.dart' as app;
import 'package:frontend/core/services/firebase_environment.dart';
import 'package:frontend/core/services/push_notification_service.dart';
import 'package:frontend/core/services/performance_trace.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import 'package:frontend/core/network/api_service.dart';
import 'package:frontend/core/di/dependency_injection.dart';
import 'package:frontend/features/auth/view/welcome_screen.dart';
import 'package:frontend/features/auth/viewmodel/auth_viewmodel.dart';
import 'package:frontend/features/projects/view/project_list_screen.dart';
import 'package:frontend/features/projects/view/review_project_screen.dart';
import 'package:frontend/features/projects/view/project_success_screen.dart';
import 'package:frontend/features/projects/viewmodel/project_view_model.dart';
import 'package:frontend/features/projects/viewmodel/create_project_view_model.dart';
import 'package:frontend/features/projects/model/project_member_option.dart';
import 'package:frontend/features/activities/model/activity.dart';
import 'package:frontend/shared/enums/user_role.dart';
import 'package:frontend/shared/widgets/app_button.dart';

const broker = 'http://127.0.0.1:8014';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Local performance on physical Android', (tester) async {
    try {
      if (!const bool.fromEnvironment('PERFORMANCE_SANDBOX') ||
          !FirebaseEnvironment.emulator ||
          FirebaseEnvironment.options.projectId != 'demo-crompton-pms') {
        throw StateError('Requires isolated emulator sandbox package');
      }
      final samples = <Map<String, dynamic>>[];
      Future<T> io<T>(Future<T> Function() operation) async {
        T? result;
        Object? error;
        await tester.runAsync(() async {
          try {
            result = await operation();
          } catch (e) {
            error = e;
          }
        });
        if (error != null) {
          throw StateError('Probe operation failed (${error.runtimeType})');
        }
        return result as T;
      }

      Future<void> until(bool Function() ready, {int seconds = 30}) async {
        final watch = Stopwatch()..start();
        while (!ready() && watch.elapsed < Duration(seconds: seconds)) {
          await tester.pump();
          await io(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        if (!ready()) throw StateError('Expected application state timed out');
        await tester.pump();
      }

      Future<void> report(String label, double ms) async {
        samples.add({'stage': label, 'ms': ms});
        await io(
          () => http.post(
            Uri.parse('$broker/stage'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'stage': label, 'ms': ms}),
          ),
        );
      }

      Future<void> measured(
        String label,
        Future<void> Function() operation,
      ) async {
        final watch = Stopwatch()..start();
        await operation();
        await report(label, watch.elapsedMicroseconds / 1000);
      }

      final fixture =
          jsonDecode(
                (await io(() => http.get(Uri.parse('$broker/fixtures')))).body,
              )
              as Map;
      await io(() => SecureStorageService().clearActiveUser());
      final startup = Stopwatch()..start();
      await io(() => app.main());
      await until(() => find.byType(WelcomeScreen).evaluate().isNotEmpty);
      await report('startup.to_welcome', startup.elapsedMicroseconds / 1000);
      BuildContext context() =>
          PushNotificationService.instance.navigatorKey.currentContext!;
      final auth = context().read<AuthViewModel>();
      await measured('login.confirmed', () async {
        final result = await io(
          () => auth.login(
            employeeCode: 'CAP001',
            password: fixture['password'] as String,
          ),
        );
        if (!result.success) throw StateError('Synthetic login failed');
        await tester.pump();
      });
      final api = ApiService();
      for (var i = 0; i < 5; i++) {
        await measured('projects.screen_ready', () async {
          final vm = context().read<ProjectViewModel>();
          // Cold provider state, real transport cache remains in place on repeats.
          vm.reset();
          Navigator.of(context()).push(
            MaterialPageRoute<void>(builder: (_) => const ProjectListScreen()),
          );
          await until(
            () =>
                find.byType(ProjectListScreen).evaluate().isNotEmpty &&
                vm.loadState == ProjectLoadState.success,
          );
          if (vm.projects.isEmpty) throw StateError('Missing seeded project');
        });
        Navigator.of(context()).pop();
        await tester.pumpAndSettle();
        for (final endpoint in [
          '/activities',
          '/employees?staffOnly=true',
          '/notifications/unread-count',
          '/modules?projectId=100',
        ]) {
          await measured('read.${endpoint.split('?').first}', () async {
            final response = await io(() => api.get(endpoint));
            if (response.statusCode != 200) {
              throw StateError('Read probe failed');
            }
          });
        }
      }
      for (var i = 0; i < 5; i++) {
        final vm = CreateProjectViewModel(
          projectRepository: DependencyInjection.projectRepository,
          moduleRepository: DependencyInjection.moduleRepository,
        );
        final unique = DateTime.now().microsecondsSinceEpoch;
        vm.setProjectCode('DEVICE-$unique');
        vm.setProjectName('Synthetic speed probe');
        vm.setModuleName('Design');
        vm.setBuildingClassification('COMMERCIAL');
        vm.setStructureClassification('RCC');
        vm.setNumberOfFloorsText('2');
        vm.setAreaText('100');
        vm.setHoursText('10');
        vm.setMinutesText('0');
        vm.setSecondsText('0');
        vm.setStartDate(DateTime.now());
        vm.setEndDate(DateTime.now().add(const Duration(days: 10)));
        vm.setTeamLeader(
          const ProjectMemberOption(
            id: 3,
            employeeCode: 'TL001',
            name: 'Synthetic',
            email: '',
            role: UserRole.teamLeader,
          ),
        );
        vm.toggleEmployee(
          const ProjectMemberOption(
            id: 4,
            employeeCode: 'EMP001',
            name: 'Synthetic',
            email: '',
            role: UserRole.employee,
          ),
        );
        vm.toggleBillableActivity(
          const Activity(id: 1, name: 'Design', active: true),
        );
        Navigator.of(context()).push(
          MaterialPageRoute<void>(
            builder: (_) => ChangeNotifierProvider.value(
              value: vm,
              child: const ReviewProjectScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final button = find.byWidgetPredicate((widget) =>
            widget is AppButton && widget.text == 'Confirm & Create');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final watch = Stopwatch()..start();
        await tester.tap(button);
        await tester.pump();
        final feedbackMs = watch.elapsedMicroseconds / 1000;
        expect(vm.isSubmitting, isTrue);
        expect(tester.widget<AppButton>(button).isLoading, isTrue);
        await until(
          () => find.byType(ProjectSuccessScreen).evaluate().isNotEmpty,
          seconds: 45,
        );
        final totalMs = watch.elapsedMicroseconds / 1000;
        expect(vm.createdModule, isNotNull);
        await report('project.tap_to_loading_frame', feedbackMs);
        await report('project.tap_to_confirmed_success_frame', totalMs);
        // Dispose the completed route without triggering another mutation.
        Navigator.of(context()).pop();
        await tester.pumpAndSettle();
      }
      final client = http.Client();
      try {
        for (var i = 0; i < 5; i++) {
          await measured('hosted.health', () async {
            final response = await io(
              () => client
                  .get(
                    Uri.parse(
                      'https://comten-production.up.railway.app/health',
                    ),
                  )
                  .timeout(const Duration(seconds: 20)),
            );
            if (response.statusCode != 200) {
              throw StateError('Hosted health failed');
            }
          });
        }
      } finally {
        client.close();
      }
      await io(
        () => http.post(
          Uri.parse('$broker/result'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'passed': true,
            'samples': samples,
            'tracing': PerformanceTrace.enabled,
            'scope':
                'Physical Android + USB local emulators; hosted health read-only; no cloud mutation',
          }),
        ),
      );
    } catch (_) {
      await tester.runAsync(
        () => http.post(
          Uri.parse('$broker/result'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'passed': false}),
        ),
      );
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
