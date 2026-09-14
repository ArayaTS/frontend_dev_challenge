import 'dart:async';

import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../repository/order_repo.dart';
import '../service/api_exception.dart';
import '../util/log_service.dart';
import 'countdown_ticker_service.dart';

/// App-wide cart. Lives for the whole session.
///
/// Adding/changing quantity reserves stock (F-3): the UI updates
/// immediately (optimistic), then reconciles once the backend confirms or
/// rejects the reservation. Invariant: whenever a line's `reservation` is
/// non-null, it covers at least that line's current `quantity` — see
/// CartItemModel.
class CartService extends GetxService {
  final CountdownTickerService ticker;
  final OrderRepo orderRepo;

  CartService({required this.ticker, required this.orderRepo});

  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  Worker? _expirySweepWorker;

  @override
  void onInit() {
    super.onInit();
    // Piggybacks on the same shared tick every live countdown uses, instead
    // of running its own timer, to catch items expiring while the user is
    // on a screen that isn't showing them at all.
    _expirySweepWorker = ever(ticker.tick, (_) => _sweepExpired());
  }

  @override
  void onClose() {
    _expirySweepWorker?.dispose();
    super.onClose();
  }

  void _sweepExpired() {
    final expiredFlash =
        items.where((i) => i.deal.isFlashSaleExpired).toList(growable: false);
    final expiredReservation = items
        .where((i) =>
            !i.deal.isFlashSaleExpired &&
            i.reservation != null &&
            i.reservation!.isExpired)
        .toList(growable: false);
    if (expiredFlash.isEmpty && expiredReservation.isEmpty) return;

    for (final item in expiredFlash) {
      items.remove(item);
    }
    for (final item in expiredReservation) {
      items.remove(item);
    }
    _recount();

    if (expiredFlash.isNotEmpty) {
      Get.snackbar(
        'Flash sale ended',
        expiredFlash.length == 1
            ? '${expiredFlash.first.deal.name} was removed from your bag — '
                'the flash sale ended.'
            : '${expiredFlash.length} flash deals were removed from your '
                'bag — their sales ended.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
    if (expiredReservation.isNotEmpty) {
      Get.snackbar(
        'Reservation expired',
        expiredReservation.length == 1
            ? '${expiredReservation.first.deal.name} was removed from your '
                'bag — its hold expired. Add it again if you still want it.'
            : '${expiredReservation.length} items were removed from your '
                'bag — their holds expired.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  String _friendlyMessage(Object error) {
    if (error is ApiException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  /// Adds one unit of [deal] to the bag. Updates the line immediately, then
  /// reserves stock in the background; a failed reservation rolls the
  /// quantity (and the line itself, if it was new) back and surfaces a
  /// plain-language message.
  Future<void> add(DealModel deal) async {
    if (deal.isFlashSaleExpired) {
      LogService.log('cart: refusing to add expired flash deal ${deal.id}');
      return;
    }
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    final previousQuantity = existing?.quantity ?? 0;
    final newQuantity = previousQuantity + 1;
    if (newQuantity > deal.quantityLeft) {
      LogService.log('cart: cannot add more of deal ${deal.id}');
      return;
    }

    final isNewLine = existing == null;
    final item = existing ?? CartItemModel(deal: deal, quantity: 0);
    item.quantity = newQuantity;
    item.isReserving = true;
    if (isNewLine) items.add(item);
    items.refresh();
    _recount();

    try {
      final reservation =
          await orderRepo.reserve(deal.id, quantity: newQuantity);
      final oldReservationId = item.reservation?.id;
      item.reservation = reservation;
      if (oldReservationId != null) {
        unawaited(orderRepo.releaseReservation(oldReservationId));
      }
    } catch (e) {
      LogService.error('reserve failed for deal ${deal.id}', e);
      item.quantity = previousQuantity;
      if (isNewLine || item.quantity <= 0) {
        items.remove(item);
      }
      Get.snackbar('Could not add to bag', _friendlyMessage(e),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      item.isReserving = false;
      items.refresh();
      _recount();
    }
  }

  /// Removes one unit of [dealId]. If that empties the line, releases its
  /// hold entirely; otherwise re-reserves for the smaller quantity so the
  /// hold never covers more than what's actually in the bag.
  Future<void> decrement(int dealId) async {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    final previousQuantity = existing.quantity;
    final newQuantity = previousQuantity - 1;

    if (newQuantity <= 0) {
      final reservationId = existing.reservation?.id;
      items.remove(existing);
      _recount();
      if (reservationId != null) {
        unawaited(orderRepo.releaseReservation(reservationId));
      }
      return;
    }

    existing.quantity = newQuantity;
    existing.isReserving = true;
    items.refresh();
    _recount();

    try {
      final reservation =
          await orderRepo.reserve(dealId, quantity: newQuantity);
      final oldReservationId = existing.reservation?.id;
      existing.reservation = reservation;
      if (oldReservationId != null) {
        unawaited(orderRepo.releaseReservation(oldReservationId));
      }
    } catch (e) {
      // Keep the old (larger) reservation and quantity rather than leaving
      // the line under-covered — over-holding is harmless (checkout only
      // checks that a reservation id is valid, not that it matches the
      // final quantity), losing an already-secured item to a failed
      // "shrink" is not.
      LogService.error('re-reserve failed while decrementing deal $dealId', e);
      existing.quantity = previousQuantity;
      Get.snackbar('Could not update your bag', _friendlyMessage(e),
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      existing.isReserving = false;
      items.refresh();
      _recount();
    }
  }

  void remove(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    final reservationId = existing.reservation?.id;
    items.remove(existing);
    _recount();
    if (reservationId != null) {
      unawaited(orderRepo.releaseReservation(reservationId));
    }
  }

  void clear() {
    final reservationIds = items
        .map((i) => i.reservation?.id)
        .whereType<String>()
        .toList(growable: false);
    items.clear();
    _recount();
    for (final id in reservationIds) {
      unawaited(orderRepo.releaseReservation(id));
    }
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }
}
