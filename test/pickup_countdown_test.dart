import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/order/widget/pickup_countdown.dart';

void main() {
  testWidgets(
      'RES-102: does not call setState (or leak its timer) after the widget '
      'is disposed', (tester) async {
    final pickupStart = DateTime.now().add(const Duration(minutes: 5));
    await tester.pumpWidget(
      MaterialApp(home: PickupCountdown(pickupStart: pickupStart)),
    );

    // Simulate navigating back: the widget leaves the tree.
    await tester.pumpWidget(const SizedBox());

    // Let the periodic timer's next tick fire, if it is still alive.
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });
}
