import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/search/search_deals_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/service/fake_api_service.dart';

DealModel _dealNamed(String name) => DealModel.fromJson({
      'id': name.hashCode,
      'name': name,
      'description': '',
      'imageUrl': '',
      'originalPrice': 100,
      'price': 50,
      'currencyCode': 'THB',
      'quantityLeft': 1,
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

/// Lets the test decide exactly when each query's response resolves, so we
/// can reproduce "an earlier, shorter query's response arrives after a
/// later, longer query's response" without depending on real timers.
class _ControlledDealRepo extends DealRepo {
  _ControlledDealRepo() : super(api: FakeApiService());

  final _pending = <String, Completer<List<DealModel>>>{};

  @override
  Future<List<DealModel>> search(String query) {
    final completer = Completer<List<DealModel>>();
    _pending[query] = completer;
    return completer.future;
  }

  void resolve(String query, List<DealModel> result) {
    _pending[query]!.complete(result);
  }
}

void main() {
  test(
      'RES-101: a stale response for an earlier, shorter query does not '
      'clobber the result of a newer query that resolved first', () async {
    final repo = _ControlledDealRepo();
    final controller = SearchDealsController(dealRepo: repo);

    // User types "s" then quickly "su" — both requests are now in flight.
    controller.onQueryChanged('s');
    controller.onQueryChanged('su');

    // The real backend makes broader (shorter) queries slower, so "su"
    // resolves first even though "s" was requested first.
    repo.resolve('su', [_dealNamed('Sushi Box')]);
    await Future<void>.delayed(Duration.zero);
    repo.resolve('s', [_dealNamed('Some Bakery Item')]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.results.map((d) => d.name), ['Sushi Box']);
  });
}
