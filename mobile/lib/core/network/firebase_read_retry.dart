import 'dart:async';
import 'package:firebase_core/firebase_core.dart';

bool isTransientFirebaseReadError(Object error) =>
    error is TimeoutException ||
    (error is FirebaseException &&
        const {'unavailable', 'deadline-exceeded'}.contains(error.code));

/// Retry only reads that failed because their connection was not ready.
/// Fresh request scopes must be created by [read] on every attempt.
Future<T> retryFirebaseRead<T>(
  Future<T> Function() read, {
  Future<void> Function(Duration)? wait,
}) async {
  final delay = wait ?? Future<void>.delayed;
  for (var attempt = 0; ; attempt++) {
    try {
      return await read();
    } catch (error) {
      if (attempt == 3 || !isTransientFirebaseReadError(error)) rethrow;
      await delay(Duration(milliseconds: 250 * (1 << attempt)));
    }
  }
}
