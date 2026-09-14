import 'deal_model.dart';
import 'reservation_model.dart';

class CartItemModel {
  final DealModel deal;
  int quantity;

  /// Stock hold for this line item. Invariant maintained by CartService:
  /// whenever non-null, it covers at least [quantity] units. Null only
  /// during the brief optimistic window before the first reserve() for a
  /// new line resolves.
  ReservationModel? reservation;

  /// True while a reserve() call for this line is in flight — lets the UI
  /// show that the quantity just changed optimistically and hasn't been
  /// confirmed by the backend yet.
  bool isReserving;

  CartItemModel({
    required this.deal,
    this.quantity = 1,
    this.reservation,
    this.isReserving = false,
  });

  num get lineTotal => deal.price * quantity;
}
