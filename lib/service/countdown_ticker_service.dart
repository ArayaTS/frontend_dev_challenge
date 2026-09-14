import 'dart:async';

import 'package:get/get.dart';

/// Ticks once a second so every live countdown (flash rail, home feed
/// cards, details screen) — and the cart's own expiry sweep — share a
/// single Timer instead of each one starting its own. The home feed must
/// stay smooth with 100+ visible countdowns, so per-second work has to be
/// one shared tick, not N independent timers.
class CountdownTickerService extends GetxService {
  final tick = 0.obs;
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick.value++);
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
