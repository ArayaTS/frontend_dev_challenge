import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/cart/cart_controller.dart';
import 'package:rescu/model/cart_item_model.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/order_model.dart';
import 'package:rescu/model/reservation_model.dart';
import 'package:rescu/repository/order_repo.dart';
import 'package:rescu/service/api_exception.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/countdown_ticker_service.dart';
import 'package:rescu/service/fake_api_service.dart';

DealModel _deal(int id, {int quantityLeft = 5}) => DealModel.fromJson({
      'id': id,
      'name': 'Deal $id',
      'description': '',
      'imageUrl': '',
      'originalPrice': 100,
      'price': 50,
      'currencyCode': 'THB',
      'quantityLeft': quantityLeft,
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
      'flashSaleEndsAt': null,
    });

/// Lets tests control exactly when reserve() resolves and whether it
/// succeeds, instead of depending on FakeApiService's built-in randomness.
class _ControlledOrderRepo extends OrderRepo {
  _ControlledOrderRepo() : super(api: FakeApiService());

  bool shouldFail = false;
  String failMessage = 'Could not reserve: someone grabbed the last one.';
  int reserveCallCount = 0;
  final releasedIds = <String>[];
  Completer<void>? gate;
  int _seq = 0;

  @override
  Future<ReservationModel> reserve(int dealId, {int quantity = 1}) async {
    reserveCallCount++;
    if (gate != null) await gate!.future;
    if (shouldFail) {
      throw ApiException(failMessage, statusCode: 409);
    }
    return ReservationModel(
      id: 'res_${++_seq}',
      dealId: dealId,
      quantity: quantity,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<void> releaseReservation(String reservationId) async {
    releasedIds.add(reservationId);
  }

  int? checkoutFailStatusCode;

  @override
  Future<OrderModel> checkout(List<CartItemModel> items) async {
    if (checkoutFailStatusCode != null) {
      throw ApiException('simulated checkout failure',
          statusCode: checkoutFailStatusCode!);
    }
    return OrderModel.fromJson({
      'id': 1,
      'dealId': items.first.deal.id,
      'dealName': items.first.deal.name,
      'storeName': items.first.deal.storeName,
      'imageUrl': '',
      'status': 'CONFIRMED',
      'quantity': items.first.quantity,
      'total': 100,
      'currencyCode': 'THB',
      'pickupStart': DateTime.now().toIso8601String(),
      'pickupEnd': DateTime.now().toIso8601String(),
    });
  }
}

void main() {
  test(
      'F-3: add() shows the item immediately (optimistic) and confirms the '
      'reservation once the backend responds', () async {
    final repo = _ControlledOrderRepo()..gate = Completer<void>();
    final cart = CartService(ticker: CountdownTickerService(), orderRepo: repo);

    final future = cart.add(_deal(1));

    // Optimistic: visible before the reservation call has resolved.
    expect(cart.items, hasLength(1));
    expect(cart.items.single.quantity, 1);
    expect(cart.items.single.isReserving, isTrue);
    expect(cart.items.single.reservation, isNull);

    repo.gate!.complete();
    await future;

    expect(cart.items.single.isReserving, isFalse);
    expect(cart.items.single.reservation, isNotNull);
    expect(cart.items.single.reservation!.dealId, 1);
  });

  testWidgets(
      'F-3: add() rolls a new line back out of the bag if the reservation '
      'fails, with a non-technical message', (tester) async {
    Get.testMode = true;
    await tester.pumpWidget(GetMaterialApp(home: Container()));

    final repo = _ControlledOrderRepo()..shouldFail = true;
    final cart = CartService(ticker: CountdownTickerService(), orderRepo: repo);

    await cart.add(_deal(1));
    await tester.pump();

    expect(cart.items, isEmpty);
    expect(find.text('Could not add to bag'), findsOneWidget);

    // Let the snackbar's own show/dismiss animation and timer finish so
    // nothing is left pending when the test ends.
    await tester.pump(const Duration(seconds: 4));

    Get.reset();
  });

  testWidgets(
      'F-3: a failed reservation on an increment rolls back just the '
      'quantity, keeping the line and its existing reservation',
      (tester) async {
    Get.testMode = true;
    await tester.pumpWidget(GetMaterialApp(home: Container()));

    final repo = _ControlledOrderRepo();
    final cart = CartService(ticker: CountdownTickerService(), orderRepo: repo);
    final deal = _deal(1);

    await cart.add(deal); // succeeds
    final firstReservation = cart.items.single.reservation;
    expect(firstReservation, isNotNull);

    repo.shouldFail = true;
    await cart.add(deal); // second unit fails
    await tester.pump();

    expect(cart.items, hasLength(1));
    expect(cart.items.single.quantity, 1);
    expect(cart.items.single.reservation, same(firstReservation));

    await tester.pump(const Duration(seconds: 4));

    Get.reset();
  });

  test('F-3: decrementing to zero removes the line and releases its hold',
      () async {
    final repo = _ControlledOrderRepo();
    final cart = CartService(ticker: CountdownTickerService(), orderRepo: repo);
    await cart.add(_deal(1));
    final reservationId = cart.items.single.reservation!.id;

    await cart.decrement(1);

    expect(cart.items, isEmpty);
    expect(repo.releasedIds, [reservationId]);
  });

  test(
      'F-3: decrementing above zero re-reserves for the smaller quantity '
      'and releases the old hold', () async {
    final repo = _ControlledOrderRepo();
    final cart = CartService(ticker: CountdownTickerService(), orderRepo: repo);
    final deal = _deal(1);
    await cart.add(deal);
    await cart.add(deal);
    // add()'s own logic already released the very first reservation when
    // it superseded it with one covering both units — this test is about
    // what decrement() does to *that* current reservation.
    final reservationBeforeDecrement = cart.items.single.reservation!.id;
    expect(cart.items.single.quantity, 2);

    await cart.decrement(1);

    expect(cart.items.single.quantity, 1);
    expect(
        cart.items.single.reservation!.id, isNot(reservationBeforeDecrement));
    expect(repo.releasedIds, contains(reservationBeforeDecrement));
  });

  testWidgets(
      'F-3: checkout surfaces a plain-language message and leaves the bag '
      'in place when a reservation expired mid-checkout (410)', (tester) async {
    Get.testMode = true;
    await tester.pumpWidget(GetMaterialApp(home: Container()));

    final repo = _ControlledOrderRepo()..checkoutFailStatusCode = 410;
    final cart = CartService(ticker: CountdownTickerService(), orderRepo: repo);
    cart.items.add(CartItemModel(
      deal: _deal(1),
      reservation: ReservationModel(
        id: 'res_x',
        dealId: 1,
        quantity: 1,
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      ),
    ));
    final controller = CartController(cartService: cart, orderRepo: repo);

    await controller.checkout();
    await tester.pump();

    expect(find.text('Your bag changed'), findsOneWidget);
    // Checkout failing outright must not silently empty the bag — the
    // sweep (not checkout) is what removes a genuinely expired line.
    expect(cart.items, hasLength(1));

    await tester.pump(const Duration(seconds: 5));
    Get.reset();
  });
}
