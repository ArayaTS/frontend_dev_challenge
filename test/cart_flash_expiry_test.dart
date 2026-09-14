import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/model/cart_item_model.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/order_repo.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/countdown_ticker_service.dart';
import 'package:rescu/service/fake_api_service.dart';

DealModel _dealJson(int id, {String? flashSaleEndsAt}) => DealModel.fromJson({
      'id': id,
      'name': 'Deal $id',
      'description': '',
      'imageUrl': '',
      'originalPrice': 100,
      'price': 50,
      'currencyCode': 'THB',
      'quantityLeft': 3,
      'storeId': 1,
      'storeName': 'Test Store',
      'storeAddress': '',
      'lat': 0,
      'lng': 0,
      'rating': null,
      'tags': const <String>[],
      'pickupWindow': {
        'start': '2026-01-01T10:00:00.000Z',
        'end': '2026-01-01T12:00:00.000Z',
      },
      'flashSaleEndsAt': flashSaleEndsAt,
    });

void main() {
  test('F-1: adding an already-expired flash deal is refused', () {
    final cart = CartService(
        ticker: CountdownTickerService(),
        orderRepo: OrderRepo(api: FakeApiService()));
    final expired = _dealJson(1,
        flashSaleEndsAt: DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String());

    cart.add(expired);

    expect(cart.items, isEmpty);
  });

  testWidgets(
      'F-1: a flash-sale item already in the cart is removed once its '
      'countdown expires, leaving other items untouched', (tester) async {
    Get.testMode = true;
    // Get.snackbar needs a mounted GetMaterialApp to show into.
    await tester.pumpWidget(GetMaterialApp(home: Container()));

    final ticker = CountdownTickerService();
    final cart = CartService(
        ticker: ticker, orderRepo: OrderRepo(api: FakeApiService()));
    cart.onInit(); // wires up the expiry sweep (normally done by Get.put)

    final live = _dealJson(1,
        flashSaleEndsAt:
            DateTime.now().add(const Duration(minutes: 5)).toIso8601String());
    final expiring = _dealJson(2,
        flashSaleEndsAt: DateTime.now()
            .add(const Duration(milliseconds: 1))
            .toIso8601String());
    final regular = _dealJson(3);

    cart.items.addAll([
      CartItemModel(deal: live),
      CartItemModel(deal: expiring),
      CartItemModel(deal: regular),
    ]);

    // Let real time pass "expiring"'s deadline (see flash_countdown_test.dart
    // for why this needs runAsync rather than a bare await), then simulate a
    // shared tick and let the snackbar animate in.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    ticker.tick.value++;
    await tester.pump();

    expect(cart.items.map((i) => i.deal.id), containsAll([1, 3]));
    expect(cart.items.any((i) => i.deal.id == 2), isFalse);
    expect(find.text('Flash sale ended'), findsOneWidget);

    ticker.onClose();
    // Let the snackbar's own timer finish before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });
}
