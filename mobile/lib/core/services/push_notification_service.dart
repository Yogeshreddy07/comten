import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'firebase_environment.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

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

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: FirebaseEnvironment.options);
  // Android displays notification payloads. Authenticated UI fetches the record
  // after a tap; the background isolate never opens another account's cache.
}

/// Wires up Home Screen (FCM) push notifications: requests permission,
/// registers this device's token with the backend, shows a banner while the
/// app is in the foreground (FCM doesn't auto-display those), and deep-links
/// to the right screen when a notification is tapped in any app state - see
/// [NotificationNavigator]. A single instance lives for the app's lifetime;
/// [initialize] runs once in main.dart, [syncToken] runs after authentication
/// and retries on resume, and [unregister] runs on logout.
class PushNotificationService with WidgetsBindingObserver {
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
  String? _registeredUid;
  StreamSubscription<String>? _tokenSubscription;
  Future<void>? _registration;
  Future<void>? _tokenSync;
  String? _employeeCode;
  int _syncGeneration = 0;
  static const _deviceStorage=FlutterSecureStorage();
  static const _resetKey='push_token_requires_reset';

  Future<void> initialize() async {
    try { await _initializeNative(); }
    on FirebaseException catch(e) { debugPrint('Push initialization unavailable: ${e.code}'); }
    on PlatformException catch(e) { debugPrint('Push initialization unavailable: ${e.code}'); }
  }

  Future<void> _initializeNative() async {
    if (kIsWeb || FirebaseEnvironment.emulator) return;
    if (_initialized) return;
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);

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

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    // Foreground: FCM delivers the message but never shows anything itself,
    // so we show it manually via flutter_local_notifications.
    FirebaseMessaging.onMessage.listen(showForegroundNotification);

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
    if (initialMessage != null) {
      _pendingInitialMessageData = initialMessage.data;
    }
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final employeeCode = _employeeCode;
    if (state == AppLifecycleState.resumed && employeeCode != null) {
      unawaited(syncToken(employeeCode));
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
  Future<void> syncToken(String employeeCode) {
    _employeeCode = employeeCode;
    // Login routing and lifecycle resume may request the same sync together.
    return _tokenSync ??= _syncTokenSafely(employeeCode).whenComplete(() {
      _tokenSync = null;
    });
  }

  Future<void> _syncTokenSafely(String employeeCode) async {
    final generation = _syncGeneration;
    await requestPermission();
    if (generation != _syncGeneration) return;
    try { await _syncToken(employeeCode); }
    on FirebaseException catch(e) { debugPrint('Push registration unavailable: ${e.code}'); }
    on PlatformException catch(e) { debugPrint('Push registration unavailable: ${e.code}'); }
    on TimeoutException { debugPrint('Push registration timed out'); }
    on Exception { debugPrint('Push registration failed; will retry on resume'); }
  }

  /// Shows the system "Allow notifications?" prompt (Android 13+) if it
  /// hasn't been answered yet. Deliberately independent of Firebase: if FCM
  /// setup fails or the emulator build is running, the prompt must still
  /// appear, otherwise Android silently drops every notification.
  Future<void> requestPermission() async {
    if (kIsWeb) return;
    try {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } on PlatformException catch (e) {
      debugPrint('Notification permission request unavailable: ${e.code}');
    }
  }

  Future<void> _syncToken(String employeeCode) async {
    final generation = _syncGeneration;
    if (FirebaseEnvironment.emulator || kIsWeb) return;
    await initialize();
    if(!_initialized) return;
    final permission=await FirebaseMessaging.instance.requestPermission();
    if(permission.authorizationStatus==AuthorizationStatus.denied) return;
    final uid=FirebaseAuth.instance.currentUser?.uid;
    if(uid==null) return;
    final previousUid=await _deviceStorage.read(key:'push_registered_uid');
    if(previousUid!=null && previousUid!=uid) await _deviceStorage.write(key:_resetKey,value:'true');
    if (generation != _syncGeneration || FirebaseAuth.instance.currentUser?.uid != uid) return;
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
    if(await _deviceStorage.read(key:_resetKey)=='true') {
      await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds:10));
      await _deviceStorage.delete(key:_resetKey);
    }
    await _tokenSubscription?.cancel();
    if (generation != _syncGeneration || FirebaseAuth.instance.currentUser?.uid != uid) return;
    // Keep listening even if the initial getToken call fails while offline.
    _tokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      if (generation != _syncGeneration) return;
      _registration=_registerToken(employeeCode, newToken,uid).catchError((Object error) {debugPrint('Push token refresh registration failed');});
    });
    final token = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds:10));
    if (token != null && generation == _syncGeneration) {
      await (_registration=_registerToken(employeeCode, token,uid));
    }
  }

  Future<void> _registerToken(String employeeCode, String token,String? uid) async {
    if(uid==null || FirebaseAuth.instance.currentUser?.uid!=uid) return;
    if (_registeredToken == token && _registeredUid==uid) return;
    final result = await _repository.registerDeviceToken(token);
    if (!result.success) {
      throw Exception('Device registration was not accepted');
    }
    if (result.success && FirebaseAuth.instance.currentUser?.uid==uid) {
      _registeredToken = token;
      _registeredUid=uid;
      await _deviceStorage.write(key:'push_registered_uid',value:uid);
      await PreferenceUtil.setFcmToken(employeeCode, token);
      // Correlate this phone with server registration without logging a token.
      debugPrint('Push device registration confirmed: ${sha256.convert(utf8.encode(token))}');
    }
  }

  /// Unregisters this device's token - call before clearing the session on
  /// logout so a signed-out device stops receiving pushes for this account.
  Future<void> unregister(String employeeCode) async {
    _employeeCode = null;
    _syncGeneration++;
    try { await _tokenSync?.timeout(const Duration(seconds:20)); }
    on Exception { debugPrint('Pending push sync ended during logout'); }
    await _tokenSubscription?.cancel(); _tokenSubscription=null;
    try { await _registration?.timeout(const Duration(seconds:10)); }
    on TimeoutException { debugPrint('Pending push registration timed out during logout'); }
    on FirebaseException { debugPrint('Pending push registration failed during logout'); }
    on PlatformException { debugPrint('Pending push registration failed during logout'); }
    on Exception { debugPrint('Pending push registration failed during logout'); }
    _registration=null;
    if (FirebaseEnvironment.emulator || kIsWeb) return;
    final token = _registeredToken ?? await PreferenceUtil.getFcmToken(employeeCode);
    if (token != null) {
      await _repository.unregisterDeviceToken(token);
    }
    // Retry token invalidation before registering a different signed-in account.
    await _deviceStorage.write(key:_resetKey,value:'true');
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
      await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds:10));
      await _deviceStorage.delete(key:_resetKey);
    } on FirebaseException { debugPrint('Push invalidation deferred until reconnection'); }
      on PlatformException { debugPrint('Push invalidation deferred until reconnection'); }
      on TimeoutException { debugPrint('Push invalidation deferred until reconnection'); }
    _registeredToken = null;
    _registeredUid=null;
  }

  @visibleForTesting
  Future<void> showForegroundNotification(RemoteMessage message) async {
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
      // Android IDs are signed 32-bit; the tag preserves the full server ID.
      (int.tryParse(message.data['notificationId']?.toString() ?? '') ?? message.hashCode) & 0x7fffffff,
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
          // Keep the alert in the tray until the user explicitly dismisses it.
          autoCancel: false,
          tag: message.data['notificationId']?.toString(),
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
    if (type.isDelayRequest) {
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
