import 'dart:async';

import 'package:get/get.dart';

import 'fake_api_service.dart';
import '../util/log_service.dart';

class AnalyticsEvent {
  final String name;
  final Map<String, dynamic> properties;
  final DateTime at;

  AnalyticsEvent(this.name, this.properties) : at = DateTime.now();

  Map<String, dynamic> toJson() => {
        'name': name,
        'properties': properties,
        'at': at.toIso8601String(),
      };
}

/// In-memory analytics sink. Events are visible on the debug screen
/// (overflow menu on Home -> "Analytics debug") and in the console.
class AnalyticsService extends GetxService {
  final FakeApiService api;

  /// Overridable only so tests don't have to wait 15 real seconds to
  /// exercise the time-based flush path.
  final Duration _batchInterval;

  AnalyticsService({
    required this.api,
    Duration batchInterval = const Duration(seconds: 15),
  }) : _batchInterval = batchInterval;

  static const _batchSize = 10;

  final events = <AnalyticsEvent>[].obs;

  /// Deal ids a `deal_impression` has already been logged for this session
  /// — at most one per deal per session, across every screen.
  final _impressedDealIds = <int>{};

  final _pendingBatch = <AnalyticsEvent>[];
  Timer? _batchTimer;

  void logEvent(String name, [Map<String, dynamic> properties = const {}]) {
    final event = AnalyticsEvent(name, properties);
    events.add(event);
    LogService.log('analytics: $name $properties');
  }

  /// Logs a `deal_impression` for [dealId], unless one was already logged
  /// for that deal this session. Queued for batched delivery rather than
  /// sent immediately — see [_flushBatch].
  void logImpression({
    required int dealId,
    required String source,
    required int position,
  }) {
    if (!_impressedDealIds.add(dealId)) return;
    final event = AnalyticsEvent('deal_impression', {
      'deal_id': dealId,
      'source': source,
      'position': position,
    });
    events.add(event);
    LogService.log('analytics: deal_impression ${event.properties}');

    _pendingBatch.add(event);
    // Starts counting from the *first* unsent event in the batch; adding
    // more events before it fires does not push the deadline back.
    _batchTimer ??= Timer(_batchInterval, _flushBatch);
    if (_pendingBatch.length >= _batchSize) {
      _flushBatch();
    }
  }

  Future<void> _flushBatch() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_pendingBatch.isEmpty) return;
    final toSend = List<AnalyticsEvent>.of(_pendingBatch);
    _pendingBatch.clear();
    await api.sendAnalyticsBatch(toSend.map((e) => e.toJson()).toList());
  }

  @override
  void onClose() {
    _batchTimer?.cancel();
    super.onClose();
  }
}
