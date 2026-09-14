import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class DealDetailsController extends GetxController {
  final DealRepo dealRepo;
  final CartService cartService;
  final AnalyticsService analytics;

  DealDetailsController({
    required this.dealRepo,
    required this.cartService,
    required this.analytics,
  });

  // Navigating from the feed passes the already-fetched DealModel as
  // `arguments` (fast path). A deep link (real or simulated) only carries
  // an `id` query parameter — nothing is in memory yet, so it must be
  // fetched. `deal` is therefore nullable until either path resolves.
  final _deal = Rxn<DealModel>();
  DealModel? get dealOrNull => _deal.value;
  DealModel get deal => _deal.value!;

  final isLoading = true.obs;
  final loadFailed = false.obs;

  final _quantityLeft = RxnInt();
  int? get quantityLeft => _quantityLeft.value;

  Worker? _cartWorker;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    final args = Get.arguments;
    if (args is DealModel) {
      _deal.value = args;
    } else {
      final id = int.tryParse(Get.parameters['id'] ?? '');
      if (id == null) {
        loadFailed.value = true;
        isLoading.value = false;
        return;
      }
      try {
        _deal.value = await dealRepo.fetchById(id);
      } catch (e) {
        LogService.error('failed to load deal $id for deep link', e);
        loadFailed.value = true;
        isLoading.value = false;
        return;
      }
    }

    _quantityLeft.value = deal.quantityLeft;
    analytics.logEvent('deal_details_view', {
      'deal_id': deal.id,
      'source': Get.parameters['source'] ?? 'unknown',
    });
    // Whenever the cart changes, re-check this deal's remaining stock so the
    // details screen never shows stale availability. Disposed in onClose —
    // `ever` is not tied to the controller's lifecycle on its own, and this
    // controller is recreated every time the screen opens.
    _cartWorker = ever(cartService.itemCount, (_) => _recheckAvailability());
    isLoading.value = false;
  }

  @override
  void onClose() {
    _cartWorker?.dispose();
    super.onClose();
  }

  Future<void> _recheckAvailability() async {
    LogService.log('re-checking availability for deal ${deal.id}');
    final fresh = await dealRepo.fetchById(deal.id);
    _quantityLeft.value = fresh.quantityLeft;
  }

  void addToCart() {
    cartService.add(deal);
    Get.snackbar(
      'Added to bag',
      '${deal.name} — pick up ${deal.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }
}
