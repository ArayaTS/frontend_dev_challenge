import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../service/analytics_service.dart';

/// Wraps a deal card and logs a `deal_impression` once it has been at
/// least 50% visible for one continuous second — per F-2. Delivery is
/// deduped and batched inside [AnalyticsService]; this widget only decides
/// *when* an impression has happened.
class ImpressionTracker extends StatefulWidget {
  final int dealId;
  final String source;
  final int position;
  final Widget child;

  const ImpressionTracker({
    super.key,
    required this.dealId,
    required this.source,
    required this.position,
    required this.child,
  });

  @override
  State<ImpressionTracker> createState() => _ImpressionTrackerState();
}

class _ImpressionTrackerState extends State<ImpressionTracker> {
  Timer? _timer;
  bool _logged = false;

  void _handleVisibility(VisibilityInfo info) {
    if (_logged) return;
    final visibleEnough = info.visibleFraction >= 0.5;
    if (visibleEnough) {
      _timer ??= Timer(const Duration(seconds: 1), () {
        _timer = null;
        if (!mounted || _logged) return;
        _logged = true;
        Get.find<AnalyticsService>().logImpression(
          dealId: widget.dealId,
          source: widget.source,
          position: widget.position,
        );
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('impression-${widget.source}-${widget.dealId}-${widget.position}'),
      onVisibilityChanged: _handleVisibility,
      child: widget.child,
    );
  }
}
