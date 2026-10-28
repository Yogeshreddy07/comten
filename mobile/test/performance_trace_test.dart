import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/core/services/performance_trace.dart';
import 'package:frontend/shared/widgets/app_button.dart';

void main() {
  test('trace scopes propagate across awaits and isolate requests', () async {
    final ids = await Future.wait(
      List.generate(
        3,
        (_) => PerformanceTrace.measure('test', () async {
          final before = PerformanceTrace.current?.id;
          await Future<void>.delayed(Duration.zero);
          expect(PerformanceTrace.current?.id, before);
          return before;
        }),
      ),
    );
    if (PerformanceTrace.enabled) expect(ids.toSet().length, 3);
    expect(PerformanceTrace.current, isNull);
  });

  test(
    'HTTP instrumentation preserves body and attaches only opaque ID',
    () async {
      final client = PerformanceHttpClient(
        MockClient((request) async {
          expect(
            request.headers['X-Request-ID'],
            PerformanceTrace.enabled
                ? matches(RegExp(r'^[a-f0-9]{32}$'))
                : isNull,
          );
          return http.Response(
            'synthetic body',
            201,
            headers: {'x-synthetic': 'yes'},
          );
        }),
      );
      final response = await PerformanceTrace.measure(
        'test',
        () => client.get(Uri.parse('https://synthetic.invalid')),
      );
      expect(response.statusCode, 201);
      expect(response.body, 'synthetic body');
      expect(response.headers['x-synthetic'], 'yes');
      client.close();
    },
  );

  testWidgets('loading button still blocks duplicate taps', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppButton(
          text: 'Synthetic',
          isLoading: true,
          onPressed: () => calls++,
        ),
      ),
    );
    await tester.tap(find.byType(AppButton));
    expect(calls, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: AppButton(text: 'Synthetic', onPressed: () => calls++),
      ),
    );
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(calls, 1);
  });
}
