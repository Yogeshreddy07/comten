import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/approvals/model/project_change_request.dart';
import '../../features/approvals/repository/approval_repository.dart';
import '../../features/approvals/view/approval_details_screen.dart';
import '../../features/billing/model/billing_entry.dart';
import '../../features/billing/model/billing_status_change_request.dart';
import '../../features/billing/repository/billing_repository.dart';
import '../../features/billing/view/billing_approval_details_screen.dart';
import '../../features/billing/view/update_billing_status_screen.dart';
import '../../features/modules/view/module_details_screen.dart';
import '../../features/notifications/model/notification_item.dart';
import '../../features/notifications/repository/notification_repository.dart';
import '../../features/notifications/utils/notification_navigator.dart';
import '../../features/notifications/view/billing_submitted_details_screen.dart';
import '../../features/notifications/view/delay_request_details_screen.dart';
import '../../shared/enums/notification_type.dart';
import '../utils/preference_util.dart';

/// Wires up Home Screen (FCM) push notifications: requests permission,
/// registers this device's token with the backend, shows a banner while the
/// app is in the foreground (FCM doesn't auto-display those), and deep-links
/// to the right screen when a notification is tapped in any app state - see
/// [NotificationNavigator]. A single instance lives for the app's lifetime;
/// [initialize] runs once in main.dart, [syncToken] runs once per sign-in
/// (see `RoleDashboardScaffold`), and [unregister] runs on logout.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  /// Attached to [MaterialApp] so notification taps can navigate without
  /// needing a `BuildContext` from wherever the tap happened to be handled.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final NotificationRepository _repository = NotificationRepository();
  final ApprovalRepository _approvalRepository = ApprovalRepository();
  final BillingRepository _billingRepository = BillingRepository();
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'comten_notifications';
  static const _channel = AndroidNotificationChannel(
    _channelId,
    'Comten Notifications',
    description: 'Timesheet, project, attendance and approval alerts',
    importance: Importance.high,
  );

  bool _initialized = false;
  String? _registeredToken;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_notify'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
        _handleTapData(data);
      },
    );

    await FirebaseMessaging.instance.requestPermission();

    // Foreground: FCM delivers the message but never shows anything itself,
    // so we show it manually via flutter_local_notifications.
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // Backgrounded (app alive, user taps the OS-rendered notification).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTapData(message.data);
    });

    // Terminated (app was launched by tapping the OS-rendered notification) -
    // held rather than handled immediately: SplashScreen's own
    // `pushReplacement`/`RoleDashboardNavigator`'s `pushAndRemoveUntil` fire
    // a couple of seconds later and would just clear away (or replace) a
    // route pushed here before then. [consumePendingInitialMessage] is what
    // actually navigates, once that stack-clearing settles.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _pendingInitialMessageData = initialMessage.data;
    }
  }

  Map<String, dynamic>? _pendingInitialMessageData;

  /// Flushes the deep link from a cold-start notification tap (see
  /// [initialize]), if any - call this once the app has actually landed on
  /// its post-auth-gate destination (dashboard / unread-notifications gate /
  /// walkthrough), i.e. right after `RoleDashboardNavigator.navigate`'s
  /// `pushAndRemoveUntil` - so the deep-linked screen lands on top of a
  /// stack that's done being cleared/replaced instead of getting wiped out
  /// by it. A no-op if there's no pending message.
  void consumePendingInitialMessage() {
    final data = _pendingInitialMessageData;
    if (data == null) return;
    _pendingInitialMessageData = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleTapData(data));
  }

  /// Registers (and keeps registered, across token refreshes) this device
  /// for [employeeCode] - call once the user is signed in.
  Future<void> syncToken(String employeeCode) async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _registerToken(employeeCode, token);
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _registerToken(employeeCode, newToken);
    });
  }

  Future<void> _registerToken(String employeeCode, String token) async {
    if (_registeredToken == token) return;
    final result = await _repository.registerDeviceToken(token);
    if (result.success) {
      _registeredToken = token;
      await PreferenceUtil.setFcmToken(employeeCode, token);
    }
  }

  /// Unregisters this device's token - call before clearing the session on
  /// logout so a signed-out device stops receiving pushes for this account.
  Future<void> unregister(String employeeCode) async {
    final token = _registeredToken ?? await PreferenceUtil.getFcmToken(employeeCode);
    if (token != null) {
      await _repository.unregisterDeviceToken(token);
    }
    _registeredToken = null;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    // A module milestone push carries the alert color (green/yellow/red at
    // 30/60/90%, see `NotificationTypeX.alertColor`) as an accent on the
    // Android notification itself, matching the in-app popup/list coloring.
    final type = NotificationTypeX.fromApiValue(message.data['type'] as String?);
    final milestonePercentRaw = message.data['milestonePercent'] as String?;
    final milestonePercent = (milestonePercentRaw != null && milestonePercentRaw.isNotEmpty)
        ? int.tryParse(milestonePercentRaw)
        : null;
    final accentColor = type == NotificationType.moduleMilestoneReached
        ? type.alertColor(milestonePercent)
        : null;

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Comten Notifications',
          channelDescription:
              'Timesheet, project, attendance and approval alerts',
          importance: Importance.high,
          priority: Priority.high,
          color: accentColor,
          colorized: accentColor != null,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  Future<void> _handleTapData(Map<String, dynamic> data) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final type = NotificationTypeX.fromApiValue(data['type'] as String?);
    final projectIdRaw = data['projectId'] as String?;
    final projectId = (projectIdRaw != null && projectIdRaw.isNotEmpty)
        ? int.tryParse(projectIdRaw)
        : null;
    final moduleIdRaw = data['moduleId'] as String?;
    final moduleId = (moduleIdRaw != null && moduleIdRaw.isNotEmpty)
        ? int.tryParse(moduleIdRaw)
        : null;

    // Reason for Delay needs the full notification (reason, submitted-by,
    // project name) to open `DelayRequestDetailsScreen` directly - the push
    // payload alone only carries type/id/projectId. Reuse `markAsRead`
    // (already the right call to make on open) since it returns the full
    // notification.
    if (type == NotificationType.delayRequested) {
      final notificationIdRaw = data['notificationId'] as String?;
      final notificationId =
          notificationIdRaw != null ? int.tryParse(notificationIdRaw) : null;
      if (notificationId != null) {
        final result = await _repository.markAsRead(notificationId);
        if (!context.mounted) return;

        final notification = result.data as NotificationItem?;
        if (notification != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DelayRequestDetailsScreen(notification: notification),
            ),
          );
          return;
        }
      }
    }

    // A module submitted for billing needs the full notification (project
    // name, module name, sender) to open `BillingSubmittedDetailsScreen`
    // directly - the push payload alone only carries type/id/projectId, so
    // fetch the full notification first (same trick as Reason for Delay
    // above) to recover it.
    if (type == NotificationType.projectSubmittedForBilling) {
      final notificationIdRaw = data['notificationId'] as String?;
      final notificationId =
          notificationIdRaw != null ? int.tryParse(notificationIdRaw) : null;
      if (notificationId != null) {
        final result = await _repository.markAsRead(notificationId);
        if (!context.mounted) return;

        final notification = result.data as NotificationItem?;
        if (notification != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BillingSubmittedDetailsScreen(notification: notification),
            ),
          );
          return;
        }
      }
    }

    // A Revised Working Hours/End Date change request the PC submitted has
    // been approved - opens that module's own Module Details page directly
    // (see [ModuleDetailsScreen]) rather than the Approval queue's read-only
    // decision screen, since the PC's real next step is looking at the
    // module itself now that the change has taken effect. moduleId is
    // already in the push payload, so no extra fetch is needed here.
    if (type == NotificationType.projectChangeApproved && moduleId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ModuleDetailsScreen(moduleId: moduleId)),
      );
      return;
    }

    // A change request needs the full request (proposed values, remarks,
    // decision) to open `ApprovalDetailsScreen` directly - the push payload
    // alone only carries type/id/projectId, not the request's own id, so
    // fetch the full notification first (same trick as Reason for Delay
    // above) to recover it. (projectChangeApproved is handled above, so
    // this now only ever fires for Requested/Rejected.)
    if (type.isChangeRequest) {
      final notificationIdRaw = data['notificationId'] as String?;
      final notificationId =
          notificationIdRaw != null ? int.tryParse(notificationIdRaw) : null;
      if (notificationId != null) {
        final markResult = await _repository.markAsRead(notificationId);
        if (!context.mounted) return;

        final changeRequestId = (markResult.data as NotificationItem?)?.changeRequestId;
        if (changeRequestId != null) {
          final requestResult = await _approvalRepository.getChangeRequestDetails(changeRequestId);
          if (!context.mounted) return;

          final request = requestResult.data as ProjectChangeRequest?;
          if (request != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ApprovalDetailsScreen(request: request)),
            );
            return;
          }
        }
      }
    }

    // A billing status reversion request the PC submitted has been approved
    // - looks up the matching BillingEntry (there is no single-module
    // billing GET, only the bulk list) and opens UpdateBillingStatusScreen
    // directly on it: the existing module-level page within Billing
    // Management, not the Approval queue's read-only decision screen.
    // moduleId is already in the push payload, so no notification re-fetch
    // is needed for the lookup itself. Falls through to the generic
    // billing-reversion handling below only if the entry can't be found.
    if (type == NotificationType.billingReversionApproved && moduleId != null) {
      final billingResult = await _billingRepository.getBillingList();
      if (!context.mounted) return;
      final entries = (billingResult.data as List<BillingEntry>?) ?? [];
      BillingEntry? found;
      for (final entry in entries) {
        if (entry.moduleId == moduleId) {
          found = entry;
          break;
        }
      }
      if (found != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => UpdateBillingStatusScreen(entry: found!)),
        );
        return;
      }
    }

    // A billing status reversion request/decision needs the full request
    // (current/proposed status, remarks, decision) to open
    // `BillingApprovalDetailsScreen` directly - the push payload alone only
    // carries type/id/projectId, not the request's own id, so fetch the
    // full notification first (same trick as Reason for Delay above) to
    // recover it. (billingReversionApproved is handled above when the
    // module can be found, so this now only ever fires for
    // Requested/Rejected, or as a fallback if that lookup failed.)
    if (type.isBillingReversion) {
      final notificationIdRaw = data['notificationId'] as String?;
      final notificationId =
          notificationIdRaw != null ? int.tryParse(notificationIdRaw) : null;
      if (notificationId != null) {
        final markResult = await _repository.markAsRead(notificationId);
        if (!context.mounted) return;

        final billingChangeRequestId =
            (markResult.data as NotificationItem?)?.billingChangeRequestId;
        if (billingChangeRequestId != null) {
          final requestResult =
              await _billingRepository.getChangeRequestDetails(billingChangeRequestId);
          if (!context.mounted) return;

          final request = requestResult.data as BillingStatusChangeRequest?;
          if (request != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BillingApprovalDetailsScreen(request: request)),
            );
            return;
          }
        }
      }
    }

    NotificationNavigator.openFor(
      context: context,
      type: type,
      projectId: projectId,
      moduleId: moduleId,
    );
  }
}
