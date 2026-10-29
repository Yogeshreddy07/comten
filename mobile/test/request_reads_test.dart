import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/request_reads.dart';
import 'package:frontend/core/network/firebase_transport.dart';

void main() {
  test(
    'one read per path per request; a new request fetches fresh data',
    () async {
      var calls = 0;
      Future<int> load(String _) async => ++calls;
      final scope = RequestReads(load);
      expect(
        await Future.wait([
          scope.read('employees/1'),
          scope.read('employees/1'),
        ]),
        [1, 1],
      );
      expect(calls, 1);
      expect(await RequestReads(load).read('employees/1'), 2);
    },
  );

  test('large graphs are bounded and failures release queued reads', () async {
    var active = 0, peak = 0;
    final gates = <Completer<void>>[];
    final reads = RequestReads<int>((path) async {
      active++;
      if (active > peak) peak = active;
      final gate = Completer<void>();
      gates.add(gate);
      try {
        await gate.future;
        if (path == '0') throw StateError('Permission denied');
        return int.parse(path);
      } finally {
        active--;
      }
    }, concurrency: 2);
    final results = Future.wait(
      List.generate(12, (i) async {
        try {
          return await reads.read('$i');
        } on StateError {
          return -1;
        }
      }),
    );
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
      expect(active, lessThanOrEqualTo(2));
      gates[i].complete();
    }
    expect(await results, [-1, ...List.generate(11, (i) => i + 1)]);
    expect(peak, 2);
  });

  test('backend routes skip direct reads; native transactions stay native', () {
    for (final route in [
      ('GET', '/billing'),
      ('PUT', '/billing/1'),
      ('GET', '/files?projectId=1'),
      ('POST', '/modules'),
      ('PUT', '/work-logs/1/approve'),
      ('PUT', '/delay-requests/1/approve'),
      ('GET', '/employees/validate-identity'),
    ]) {
      expect(
        FirebaseTransport.backendOnly(route.$1, route.$2),
        isTrue,
        reason: '$route',
      );
    }
    for (final route in [
      ('GET', '/users/me'),
      ('GET', '/projects'),
      ('GET', '/notifications/unread-count'),
      ('POST', '/attendance/check-in'),
      ('POST', '/work-logs'),
      ('PUT', '/projects/1'),
      ('PUT', '/notifications/1/read'),
      ('POST', '/notifications/device-tokens'),
    ]) {
      expect(
        FirebaseTransport.backendOnly(route.$1, route.$2),
        isFalse,
        reason: '$route',
      );
    }
  });
}
