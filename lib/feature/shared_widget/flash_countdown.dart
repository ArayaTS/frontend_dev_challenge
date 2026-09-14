import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/countdown_ticker_service.dart';

/// Live "mm:ss" (or "h:mm:ss" above an hour) countdown to [endsAt].
///
/// Subscribes to the shared [CountdownTickerService] tick rather than
/// running its own Timer, and the Obx here is scoped to just this text —
/// nothing above it in the tree rebuilds every second.
class FlashCountdown extends StatelessWidget {
  final DateTime endsAt;
  final TextStyle? style;
  final TextStyle? expiredStyle;

  /// Called once, the first time this countdown observes [endsAt] has
  /// passed. Not called if it was already expired when first built.
  final VoidCallback? onExpired;

  const FlashCountdown({
    super.key,
    required this.endsAt,
    this.style,
    this.expiredStyle,
    this.onExpired,
  });

  static String format(Duration remaining) {
    if (remaining.isNegative) return 'Expired';
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final s = remaining.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final ticker = Get.find<CountdownTickerService>();
    var alreadyExpired = endsAt.isBefore(DateTime.now());
    var notifiedExpiry = false;

    return Obx(() {
      ticker.tick.value; // depend on the shared tick; value itself unused
      final remaining = endsAt.difference(DateTime.now());
      final expired = remaining.isNegative;

      if (expired && !alreadyExpired && !notifiedExpiry) {
        notifiedExpiry = true;
        final callback = onExpired;
        if (callback != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => callback());
        }
      }
      alreadyExpired = expired;

      return Text(format(remaining), style: expired ? expiredStyle : style);
    });
  }
}
