import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/flash_countdown.dart';
import 'package:rescu/service/countdown_ticker_service.dart';

void main() {
  group('FlashCountdown.format', () {
    test('mm:ss under an hour', () {
      expect(FlashCountdown.format(const Duration(minutes: 5, seconds: 9)),
          '05:09');
      expect(FlashCountdown.format(const Duration(seconds: 3)), '00:03');
    });

    test('h:mm:ss above an hour', () {
      expect(
          FlashCountdown.format(
              const Duration(hours: 1, minutes: 2, seconds: 3)),
          '1:02:03');
    });

    test('negative duration formats as Expired', () {
      expect(FlashCountdown.format(const Duration(seconds: -1)), 'Expired');
    });
  });

  testWidgets(
      'F-1: switches to Expired and fires onExpired exactly once when the '
      'countdown crosses zero', (tester) async {
    Get.testMode = true;
    final ticker = CountdownTickerService();
    Get.put(ticker);

    var expiredCalls = 0;
    // A real buffer so the transition genuinely happens during the test,
    // since the widget reads the real wall clock (DateTime.now()) —
    // flutter_test's fake timers advance Timer firing, not DateTime.now().
    // Generous margin: pumpWidget itself can eat tens of ms of real time.
    final endsAt = DateTime.now().add(const Duration(milliseconds: 600));

    await tester.pumpWidget(MaterialApp(
      home: FlashCountdown(
        endsAt: endsAt,
        onExpired: () => expiredCalls++,
      ),
    ));

    expect(find.text('Expired'), findsNothing);

    // Let real time pass the deadline. testWidgets fakes Timer/Future.delayed
    // against a virtual clock, so a bare `await Future.delayed(...)` here
    // would hang forever with nothing to advance it — runAsync opts into
    // genuinely waiting real wall-clock time instead.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)));
    // Now let the shared ticker's (virtual) timer fire so the widget
    // re-evaluates against the real DateTime.now(), which has moved on.
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Expired'), findsOneWidget);
    expect(expiredCalls, 1);

    // A further tick must not fire onExpired again.
    await tester.pump(const Duration(seconds: 1));
    expect(expiredCalls, 1);

    // Explicitly cancel the ticker's Timer before the test framework's
    // end-of-test check for pending timers.
    ticker.onClose();
  });
}
