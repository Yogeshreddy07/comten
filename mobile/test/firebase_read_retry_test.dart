import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/network/firebase_read_retry.dart';

void main() {
  test(
    'fresh connection recovers after three transient read failures',
    () async {
      var reads = 0;
      final delays = <Duration>[];
      final result = await retryFirebaseRead(
        () async {
          reads++;
          if (reads < 4) {
            throw FirebaseException(
              plugin: 'cloud_firestore',
              code: 'unavailable',
            );
          }
          return ['Project'];
        },
        wait: (delay) async {
          delays.add(delay);
        },
      );
      expect(result, ['Project']);
      expect(reads, 4);
      expect(delays.map((d) => d.inMilliseconds), [250, 500, 1000]);
    },
  );

  test('persistent outages stop after four attempts', () async {
    var reads = 0;
    await expectLater(
      retryFirebaseRead(() async {
        reads++;
        throw TimeoutException('Connection not ready');
      }, wait: (_) async {}),
      throwsA(isA<TimeoutException>()),
    );
    expect(reads, 4);
  });

  for (final code in [
    'permission-denied',
    'unauthenticated',
    'failed-precondition',
  ]) {
    test('$code is surfaced immediately without retrying', () async {
      var reads = 0;
      final failure = FirebaseException(plugin: 'cloud_firestore', code: code);
      await expectLater(
        retryFirebaseRead(
          () async {
            reads++;
            throw failure;
          },
          wait: (_) async {
            fail('Non-transient errors must not wait');
          },
        ),
        throwsA(same(failure)),
      );
      expect(reads, 1);
    });
  }

  test('deadline exceeded can recover on the next read', () async {
    var reads = 0;
    expect(
      await retryFirebaseRead(() async {
        if (++reads == 1) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'deadline-exceeded',
          );
        }
        return 42;
      }, wait: (_) async {}),
      42,
    );
    expect(reads, 2);
  });
}
