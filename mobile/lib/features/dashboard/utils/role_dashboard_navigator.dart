import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/push_notification_service.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../shared/enums/user_role.dart';
import '../../auth/view/dashboard_screen.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../notifications/view/unread_notifications_gate_screen.dart';
import '../../notifications/viewmodel/notification_view_model.dart';
import '../../walkthrough/view/walkthrough_screen.dart';
import '../view/employee_dashboard_screen.dart';
import '../view/project_manager_dashboard_screen.dart';
import '../view/team_leader_dashboard_screen.dart';

/// Single source of truth for "which dashboard does this role land on".
///
/// Every place in the auth flow that decides where to send an authenticated
/// user (login, account activation, PIN verification, biometric
/// authentication, app restart) should go through [navigate] instead of
/// pushing a dashboard screen directly - adding a future role only means
/// adding one case in [dashboardFor], not touching every call site.
class RoleDashboardNavigator {
  RoleDashboardNavigator._();

  static Widget dashboardFor(UserRole role) {
    switch (role) {
      case UserRole.captain:
        return const DashboardScreen();
      case UserRole.projectManager:
        return const ProjectManagerDashboardScreen();
      case UserRole.teamLeader:
        return const TeamLeaderDashboardScreen();
      case UserRole.employee:
        return const EmployeeDashboardScreen();
    }
  }

  /// Replaces the entire navigation stack with the dashboard matching
  /// [role] - the same "landing screen" semantics every call site used
  /// when it pushed `DashboardScreen` directly. If the user has unread
  /// notifications, [UnreadNotificationsGateScreen] takes the dashboard's
  /// place first and hands off to it once every unread item has been
  /// viewed or dismissed. If this is the first time this employee code has
  /// reached a dashboard on this install, [WalkthroughScreen] takes
  /// precedence over both, so a first-time user sees the app tour before
  /// anything else (see `AuthViewModel.saveWalkthroughSeen`). [isAppUnlock]
  /// suppresses the walkthrough entirely - the App Lock (PIN/fingerprint)
  /// screen passes `true` since unlocking isn't a new login/account
  /// activation and shouldn't ever resurface the tour.
  static Future<void> navigate(
    BuildContext context,
    UserRole role, {
    bool isAppUnlock = false,
  }) async {
    if (!context.canPushRoute) return;

    final notificationViewModel = context.read<NotificationViewModel>();
    final authViewModel = context.read<AuthViewModel>();
    final employeeCode = authViewModel.employeeCode;
    final shouldCheckWalkthrough = !isAppUnlock && employeeCode.isNotEmpty;

    // Kicked off together rather than one after the other - the walkthrough
    // check (secure storage) doesn't depend on the unread-count result
    // (network) or vice versa, they're only combined below once both are
    // known. By the time it's actually needed (after the unread-count/
    // notifications work below), this has typically already finished in
    // the background.
    //
    // The count fetch is bounded to a few seconds: it's the one piece of
    // data this function truly cannot proceed without (it decides whether
    // to route through UnreadNotificationsGateScreen at all), but a slow or
    // cold backend must never be able to hold up login/activation/app-unlock
    // navigation indefinitely for the sake of a badge count. On timeout this
    // navigation simply proceeds as if there were no unread notifications -
    // nothing is lost, the real count/list still loads normally the next
    // time the dashboard or Notifications screen fetches it.
    final unreadCountFuture = notificationViewModel
        .fetchUnreadCount()
        .timeout(const Duration(seconds: 3), onTimeout: () {});
    final walkthroughSeenFuture = shouldCheckWalkthrough
        ? authViewModel.getWalkthroughSeen(employeeCode)
        : Future.value(true);

    await unreadCountFuture;
    if (!context.mounted) return;

    // Deliberately not awaited: UnreadNotificationsGateScreen already
    // renders its own loading state and reacts to NotificationViewModel via
    // context.watch, so it can fetch the full list itself once it's on
    // screen. Blocking navigation on this second, larger round trip (on top
    // of the unread-count call above) was the main source of the multi-
    // second delay after login/activation/app-unlock - the gate screen was
    // always able to show its own spinner while this finishes, it just
    // wasn't given the chance to.
    if (notificationViewModel.unreadCount > 0) {
      unawaited(notificationViewModel.fetchNotifications());
    }

    final dashboard = dashboardFor(role);
    Widget next = notificationViewModel.unreadCount > 0
        ? UnreadNotificationsGateScreen(dashboard: dashboard)
        : dashboard;

    final alreadySeenWalkthrough = await walkthroughSeenFuture;
    if (shouldCheckWalkthrough && !alreadySeenWalkthrough) {
      next = WalkthroughScreen(role: role, employeeCode: employeeCode, next: next);
    }
    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => next),
      (route) => false,
    );

    // A cold-start notification tap's deep link (see
    // `PushNotificationService.initialize`) was held back exactly so it
    // wouldn't be wiped out by the `pushAndRemoveUntil` above - safe to
    // flush now that this is done clearing/replacing the stack.
    PushNotificationService.instance.consumePendingInitialMessage();
  }
}
