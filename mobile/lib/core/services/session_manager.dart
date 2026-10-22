import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/activities/viewmodel/activity_view_model.dart';
import '../../features/approvals/viewmodel/approval_view_model.dart';
import '../../features/attendance/viewmodel/attendance_team_view_model.dart';
import '../../features/attendance/viewmodel/attendance_view_model.dart';
import '../../features/auth/view/login_screen.dart';
import '../../features/auth/viewmodel/auth_viewmodel.dart';
import '../../features/billing/viewmodel/billing_approval_view_model.dart';
import '../../features/billing/viewmodel/billing_view_model.dart';
import '../../features/employees/viewmodel/employee_view_model.dart';
import '../../features/modules/viewmodel/module_view_model.dart';
import '../../features/notifications/viewmodel/notification_view_model.dart';
import '../../features/projects/viewmodel/project_view_model.dart';
import '../../features/settings/viewmodel/settings_view_model.dart';
import '../../features/worklogs/viewmodel/work_log_approval_view_model.dart';
import '../../features/worklogs/viewmodel/work_log_view_model.dart';
import '../../shared/constants/app_strings.dart';
import '../../shared/dialogs/session_invalidated_dialog.dart';
import 'push_notification_service.dart';

/// Reacts to this device's session being superseded by a newer login on
/// another device (see the backend's `JwtFilter`/`User#activeSessionToken`):
/// every authenticated call goes through `ApiService`, which recognizes the
/// specific 401 this triggers and calls [handleSessionInvalidated] here -
/// clears local auth data, bounces to [LoginScreen], and shows the "logged
/// in from another device" message. A single instance for the app's
/// lifetime, reusing [PushNotificationService]'s navigator key since a
/// [MaterialApp] can only have one.
class SessionManager {
  SessionManager._();

  static final SessionManager instance = SessionManager._();

  // Dedupes a burst of concurrent in-flight requests that all get rejected
  // by the same supersession at once - not a permanent lock, since this
  // account can legitimately be superseded again later (e.g. after logging
  // back in on this device). Cleared a few seconds after firing rather than
  // tied to the next successful login, to keep this class self-contained.
  bool _handling = false;

  /// [displayMessage] is what the user sees once they land back on the login
  /// screen - the caller picks it, since the same teardown serves both
  /// "superseded by another device" and "session ended".
  Future<void> handleSessionInvalidated([String? displayMessage]) async {
    if (_handling) return;
    _handling = true;
    Future.delayed(const Duration(seconds: 3), () => _handling = false);

    final context =
        PushNotificationService.instance.navigatorKey.currentContext;
    if (context == null) return;

    await context.read<AuthViewModel>().clearActiveUser();
    if (!context.mounted) return;
    context.read<ProjectViewModel>().reset();
    context.read<ModuleViewModel>().reset();
    context.read<EmployeeViewModel>().reset();
    context.read<WorkLogViewModel>().reset();
    context.read<WorkLogApprovalViewModel>().reset();
    context.read<AttendanceViewModel>().reset();
    context.read<AttendanceTeamViewModel>().reset();
    context.read<BillingViewModel>().reset();
    context.read<BillingApprovalViewModel>().reset();
    context.read<ActivityViewModel>().reset();
    context.read<ApprovalViewModel>().reset();
    context.read<NotificationViewModel>().reset();
    context.read<SettingsViewModel>().reset();

    final navigator =
        PushNotificationService.instance.navigatorKey.currentState;
    if (navigator == null) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messageContext =
          PushNotificationService.instance.navigatorKey.currentContext;
      if (messageContext != null) {
        SessionInvalidatedDialog.show(
          messageContext,
          AppStrings.sessionInvalidatedDisplayMessage,
        );
      }
    });
  }
}
