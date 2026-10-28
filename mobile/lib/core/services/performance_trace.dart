import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Compile-time opt-in; disabled in release even if the flag is supplied.
/// Never pass labels derived from UI text, URLs, IDs, headers or payloads.
class PerformanceTrace {
  static const enabled =
      !kReleaseMode && bool.fromEnvironment('PERFORMANCE_TRACE');
  static final _key = Object();
  static final _random = Random.secure();
  final String id;
  final Stopwatch _clock = Stopwatch()..start();
  PerformanceTrace()
    : id = List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
  static PerformanceTrace? get current =>
      Zone.current[_key] as PerformanceTrace?;

  void mark(String stage, {int? durationUs}) {
    if (!enabled) return;
    debugPrint(
      jsonEncode({
        'performance': true,
        'request_id': id,
        'stage': stage,
        'elapsed_us': _clock.elapsedMicroseconds,
        'duration_us': durationUs,
      }),
    );
  }

  static Future<T> measure<T>(
    String stage,
    Future<T> Function() operation,
  ) async {
    if (!enabled) return operation();
    final trace = current ?? PerformanceTrace();
    return runZoned(() async {
      trace.mark('$stage.start');
      final watch = Stopwatch()..start();
      try {
        return await operation();
      } finally {
        trace.mark('$stage.end', durationUs: watch.elapsedMicroseconds);
      }
    }, zoneValues: {_key: trace});
  }

  static T measureSync<T>(String stage, T Function() operation) {
    if (!enabled || current == null) return operation();
    final watch = Stopwatch()..start();
    try {
      return operation();
    } finally {
      current!.mark(stage, durationUs: watch.elapsedMicroseconds);
    }
  }

  static void tap(VoidCallback callback) {
    if (!enabled) {
      callback();
      return;
    }
    final trace = PerformanceTrace();
    runZoned(() {
      trace.mark('button.tap');
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => trace.mark('button.next_frame'),
      );
      callback();
    }, zoneValues: {_key: trace});
  }
}

class PerformanceHttpClient extends http.BaseClient {
  final http.Client inner;
  PerformanceHttpClient(this.inner);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (PerformanceTrace.enabled && PerformanceTrace.current != null) {
      request.headers['X-Request-ID'] = PerformanceTrace.current!.id;
    }
    final trace = PerformanceTrace.current;
    final watch = Stopwatch()..start();
    final response = await PerformanceTrace.measure(
      'http.response_headers',
      () => inner.send(request),
    );
    if (!PerformanceTrace.enabled || trace == null) return response;
    Stream<List<int>> body() async* {
      try {
        yield* response.stream;
      } finally {
        trace.mark('http.body_end', durationUs: watch.elapsedMicroseconds);
      }
    }

    return http.StreamedResponse(
      body(),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => inner.close();
}

class PerformanceNavigationObserver extends NavigatorObserver {
  void _measure(Route<dynamic> route) {
    final trace = PerformanceTrace.current;
    if (!PerformanceTrace.enabled || trace == null) return;
    trace.mark('navigation.push');
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => trace.mark('navigation.first_frame'),
    );
    if (route is TransitionRoute<dynamic>) {
      final animation = route.animation;
      if (animation == null) return;
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          trace.mark('navigation.transition_end');
          animation.removeStatusListener(listener);
        }
      }

      animation.addStatusListener(listener);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _measure(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _measure(newRoute);
  }
}

/// Measures notification dispatch; the following frame is a presentation marker,
/// not a claim that a particular result or success message was painted.
class PerformanceNotifier extends ChangeNotifier {
  @override
  void notifyListeners() {
    final trace = PerformanceTrace.current;
    PerformanceTrace.measureSync('ui.notify_listeners', super.notifyListeners);
    if (PerformanceTrace.enabled && trace != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => trace.mark('ui.next_frame'),
      );
    }
  }
}
