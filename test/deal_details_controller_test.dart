import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/binding/deal_details_binding.dart';
import 'package:rescu/feature/deal/deal_details_screen.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/fake_api_service.dart';

DealModel _deal(int id) => DealModel.fromJson({
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
      'flashSaleEndsAt': null,
    });

class _CountingDealRepo extends DealRepo {
  _CountingDealRepo() : super(api: FakeApiService());

  int fetchByIdCalls = 0;

  @override
  Future<DealModel> fetchById(int id) async {
    fetchByIdCalls++;
    return _deal(id);
  }
}

void main() {
  testWidgets(
      'RES-103: closing deal-details screens must not leave listeners that '
      'keep re-fetching those deals on every later cart change', (tester) async {
    Get.testMode = true;
    final repo = _CountingDealRepo();
    Get.put<DealRepo>(repo);
    Get.put<CartService>(CartService());
    Get.put<AnalyticsService>(AnalyticsService());

    await tester.pumpWidget(GetMaterialApp(home: Container()));

    // View three different deals, one after another, each time going back
    // to the previous screen (as a user browsing the feed would).
    // The shimmer image placeholder animates forever while (in this test
    // environment) the network image request never resolves, so we settle
    // each transition with a bounded pump instead of pumpAndSettle().
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final id in [1, 2, 3]) {
      Get.to(() => const DealDetailsScreen(),
          binding: DealDetailsBinding(), arguments: _deal(id));
      await settle();
      Get.back();
      await settle();
    }

    repo.fetchByIdCalls = 0;

    // Something elsewhere in the app changes the cart, e.g. adding a
    // different deal from the home feed.
    Get.find<CartService>().add(_deal(999));
    await settle();

    expect(repo.fetchByIdCalls, 0,
        reason: 'no deal-details screen is open, so nothing should be '
            're-fetched when the cart changes');

    Get.reset();
  });
}
