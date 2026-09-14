import 'package:get/get.dart';

import '../../repository/order_repo.dart';
import '../../service/api_exception.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class CartController extends GetxController {
  final CartService cartService;
  final OrderRepo orderRepo;

  CartController({required this.cartService, required this.orderRepo});

  final isCheckingOut = false.obs;

  Future<void> checkout() async {
    if (cartService.items.isEmpty || isCheckingOut.value) return;
    isCheckingOut.value = true;
    try {
      final order = await orderRepo.checkout(cartService.items.toList());
      cartService.clear();
      Get.snackbar(
        'Order confirmed',
        'Order #${order.id} — pick up soon!',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on ApiException catch (e) {
      LogService.error('checkout failed', e);
      if (e.statusCode == 410) {
        // A reservation expired between being added to the bag and
        // checkout. The API doesn't say which line, and there is no
        // partial-success state to reconcile into — the whole checkout
        // simply didn't happen. Fail closed with a clear explanation;
        // CartService's own tick-driven sweep will remove the now-expired
        // line(s) (and say which) within the next second, leaving the bag
        // in a reviewable, retryable state rather than silently dropping
        // or force-completing anything.
        Get.snackbar(
          'Your bag changed',
          'One or more items\' holds expired while checking out. '
              'Please review your bag and try again.',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        );
      } else {
        Get.snackbar(
          'Checkout failed',
          e.message,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
    isCheckingOut.value = false;
  }
}
