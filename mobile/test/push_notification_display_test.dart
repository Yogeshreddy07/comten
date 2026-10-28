import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:frontend/core/services/push_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('foreground alerts reach the Android tray and remain dismissible by the user', () async {
    const data = {'notificationId': '1761642000123456', 'type': 'TIMESHEET_APPROVED', 'moduleId': '101'};
    for (var i = 0; i < 2; i++) {
      await PushNotificationService.instance.showForegroundNotification(
        RemoteMessage(data: data, notification: const RemoteNotification(title: 'Approved', body: 'Synthetic alert')),
      );
    }
    final shown = calls.where((call) => call.method == 'show').toList();
    expect(shown, hasLength(2));
    final first = Map<String, dynamic>.from(shown.first.arguments as Map);
    final second = Map<String, dynamic>.from(shown.last.arguments as Map);
    expect(first['id'], second['id']);
    expect(first['id'], inInclusiveRange(0, 0x7fffffff));
    expect(first['title'], 'Approved');
    expect(first['body'], 'Synthetic alert');
    expect(jsonDecode(first['payload'] as String), data);
    final android = Map<String, dynamic>.from(first['platformSpecifics'] as Map);
    expect(android['channelId'], 'comten_notifications');
    expect(android['tag'], data['notificationId']);
    expect(android['autoCancel'], isFalse);
    expect(android['ongoing'], isFalse);
    expect(android['timeoutAfter'], isNull);
  });

  test('messages without an alert do not create empty tray entries', () async {
    await PushNotificationService.instance.showForegroundNotification(const RemoteMessage(data: {'type': 'SYNC'}));
    expect(calls.where((call) => call.method == 'show'), isEmpty);
  });

  test('overlapping registration requests coalesce and resume retries after failure', () async {
    var requests = 0;
    final permission = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'requestNotificationsPermission') {
        requests++;
        if (requests == 1) return permission.future;
        return true;
      }
      return true;
    });
    final service = PushNotificationService.instance;
    final first = service.syncToken('SYNTHETIC');
    final second = service.syncToken('SYNTHETIC');
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(identical(first, second), isTrue);
    await pumpEventQueue();
    expect(requests, 1);
    permission.completeError(PlatformException(code: 'temporarily-unavailable'));
    await first;
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(requests, 2);
    await service.unregister('SYNTHETIC');
  });

  test('logout prevents a late permission result from restarting push sync', () async {
    final permission = Completer<bool>();
    var requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      requests++;
      return permission.future;
    });
    final service = PushNotificationService.instance;
    final sync = service.syncToken('SYNTHETIC');
    final logout = service.unregister('SYNTHETIC');
    await pumpEventQueue();
    expect(requests, 1);
    permission.complete(true);
    await sync;
    await logout;
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(requests, 1);
  });
}
