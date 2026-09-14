import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/home/home_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/paged_response_model.dart';
import 'package:rescu/repository/deal_repo.dart';
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

/// Lets the test decide exactly when each page's response resolves, so we
/// can reproduce "loadMore() for page N is still in flight when the user
/// pulls to refresh".
class _ControlledDealRepo extends DealRepo {
  _ControlledDealRepo() : super(api: FakeApiService());

  final _pending = <int, Completer<PagedResponseModel<DealModel>>>{};

  @override
  Future<PagedResponseModel<DealModel>> fetchDeals({int page = 1}) {
    final completer = Completer<PagedResponseModel<DealModel>>();
    _pending[page] = completer;
    return completer.future;
  }

  void resolvePage(int page, List<DealModel> items,
      {required int totalPages}) {
    _pending[page]!
        .complete(PagedResponseModel(items: items, page: page, totalPages: totalPages));
    _pending.remove(page);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'RES-104: a page fetched by loadMore() before a refresh must not be '
      'appended onto the list after that refresh resets it', () async {
    final repo = _ControlledDealRepo();
    final controller = HomeController(dealRepo: repo);

    // Initial load, as if the home screen had already been showing page 1.
    final initialRefresh = controller.refreshDeals();
    repo.resolvePage(1, [_deal(1), _deal(2)], totalPages: 7);
    await initialRefresh;
    expect(controller.deals.map((d) => d.id), [1, 2]);

    // User scrolls to the bottom: page 2 request goes out, but is slow.
    final loadMoreFuture = controller.loadMore();

    // User pulls to refresh while that request is still pending.
    final refreshFuture = controller.refreshDeals();
    repo.resolvePage(1, [_deal(10), _deal(11)], totalPages: 7);
    await refreshFuture;
    expect(controller.deals.map((d) => d.id), [10, 11]);

    // The stale page-2 request (from before the refresh) finally resolves.
    repo.resolvePage(2, [_deal(3), _deal(4)], totalPages: 7);
    await loadMoreFuture;

    // It must be discarded, not appended onto the freshly refreshed list.
    expect(controller.deals.map((d) => d.id), [10, 11]);
  });
}
