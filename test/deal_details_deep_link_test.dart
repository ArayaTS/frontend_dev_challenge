import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/binding/deal_details_binding.dart';
import 'package:rescu/feature/deal/deal_details_screen.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/countdown_ticker_service.dart';
import 'package:rescu/service/fake_api_service.dart';

DealModel _deal(int id) => DealModel.fromJson({
      'id': id,
      'name': 'Deal $id',
      'description': 'A great deal',
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
      'flashSaleEndsAt': null,
    });

class _StubDealRepo extends DealRepo {
  _StubDealRepo() : super(api: FakeApiService());

  @override
  Future<DealModel> fetchById(int id) async => _deal(id);
}

void main() {
  testWidgets(
      'RES-107: a deep link with only an id (no arguments) lands on the '
      'real deal page instead of crashing or showing a fallback screen',
      (tester) async {
    Get.testMode = true;
    Get.put<DealRepo>(_StubDealRepo());
    Get.put<CartService>(CartService(ticker: CountdownTickerService()));
    Get.put<AnalyticsService>(AnalyticsService(api: FakeApiService()));

    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/home',
      getPages: [
        GetPage(name: '/home', page: () => const SizedBox.shrink()),
        GetPage(
          name: '/deal',
          page: () => const DealDetailsScreen(),
          binding: DealDetailsBinding(),
        ),
      ],
    ));

    // Equivalent of opening rescu://open/deal?id=42&source=push with no
    // in-memory DealModel available — exactly what home_screen.dart's
    // "Simulate deep link…" action does, and what a real push notification
    // would do.
    Get.toNamed('/deal?id=42&source=push');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('Deal 42'), findsOneWidget);
    expect(find.text('This deal could not be found.'), findsNothing);

    Get.reset();
  });
}
