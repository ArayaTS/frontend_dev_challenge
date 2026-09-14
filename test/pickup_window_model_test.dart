import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/pickup_window_model.dart';

void main() {
  test(
      'RES-106: label shows the market\'s (Asia/Bangkok, UTC+7) local time, '
      'not the raw UTC instant', () {
    // A bakery that opens 06:00-09:30 Bangkok time. The API sends that as
    // a UTC instant, which is 7 hours earlier: 23:00 the previous day.
    final window = PickupWindowModel(
      start: DateTime.parse('2026-01-01T23:00:00.000Z'),
      end: DateTime.parse('2026-01-02T02:30:00.000Z'),
    );

    expect(window.label, '06:00 – 09:30');
  });

  test(
      'RES-106: isToday follows the market\'s calendar day, not the raw UTC '
      'day', () {
    // "Now", expressed in the market's fixed UTC+7 local time.
    final nowMarket = DateTime.now().toUtc().add(const Duration(hours: 7));

    // A pickup starting at 00:30 *today in Bangkok*. Its UTC instant falls
    // on the previous UTC calendar day (00:30 - 7h wraps to 17:30 the day
    // before), so a naive `start.day == DateTime.now().day` comparison
    // would wrongly exclude it from "Pickup today".
    final bangkokTodayJustAfterMidnight =
        DateTime.utc(nowMarket.year, nowMarket.month, nowMarket.day, 0, 30);
    final utcStart =
        bangkokTodayJustAfterMidnight.subtract(const Duration(hours: 7));

    final window = PickupWindowModel(
      start: utcStart,
      end: utcStart.add(const Duration(hours: 2)),
    );

    expect(window.isToday, isTrue);
  });
}
