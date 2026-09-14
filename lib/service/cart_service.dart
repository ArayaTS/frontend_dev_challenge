import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../util/log_service.dart';
import 'countdown_ticker_service.dart';

/// App-wide cart. Lives for the whole session.
///
/// NOTE: the starter cart is purely local — it does not reserve stock on the
/// backend. See the "Reservations" feature task in PROBLEM.md.
class CartService extends GetxService {
  final CountdownTickerService ticker;

  CartService({required this.ticker});

  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  Worker? _expirySweepWorker;

  @override
  void onInit() {
    super.onInit();
    // Piggybacks on the same shared tick every live countdown uses, instead
    // of running its own timer, to catch flash-sale items expiring while
    // the user is on a screen that isn't showing that deal at all.
    _expirySweepWorker = ever(ticker.tick, (_) => _sweepExpiredFlashDeals());
  }

  @override
  void onClose() {
    _expirySweepWorker?.dispose();
    super.onClose();
  }

  void _sweepExpiredFlashDeals() {
    final expired =
        items.where((i) => i.deal.isFlashSaleExpired).toList(growable: false);
    if (expired.isEmpty) return;
    for (final item in expired) {
      items.remove(item);
    }
    _recount();
    Get.snackbar(
      'Flash sale ended',
      expired.length == 1
          ? '${expired.first.deal.name} was removed from your bag — '
              'the flash sale ended.'
          : '${expired.length} flash deals were removed from your bag — '
              'their sales ended.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void add(DealModel deal) {
    if (deal.isFlashSaleExpired) {
      LogService.log('cart: refusing to add expired flash deal ${deal.id}');
      return;
    }
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return;
      }
      existing.quantity++;
      items.refresh();
    } else {
      items.add(CartItemModel(deal: deal));
    }
    _recount();
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      items.removeWhere((i) => i.deal.id == dealId);
    } else {
      items.refresh();
    }
    _recount();
  }

  void remove(int dealId) {
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
  }

  void clear() {
    items.clear();
    _recount();
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }
}
