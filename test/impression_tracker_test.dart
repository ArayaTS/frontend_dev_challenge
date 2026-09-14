import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/impression_tracker.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/fake_api_service.dart';
import 'package:visibility_detector/visibility_detector.dart';

class _RecordingApiService extends FakeApiService {
  final batches = <List<Map<String, dynamic>>>[];

  @override
  Future<void> sendAnalyticsBatch(List<Map<String, dynamic>> events) async {
    batches.add(events);
  }
}

bool _hasImpression(AnalyticsService analytics, int dealId) =>
    analytics.events.any((e) =>
        e.name == 'deal_impression' && e.properties['deal_id'] == dealId);

void main() {
  setUp(() {
    // The package throttles visibility callbacks by default; drive them
    // synchronously in tests instead.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets(
      'F-2: logs an impression once a card has been >=50% visible for a '
      'continuous second, not before', (tester) async {
    Get.testMode = true;
    final analytics = Get.put(AnalyticsService(api: _RecordingApiService()));

    await tester.pumpWidget(MaterialApp(
      home: ImpressionTracker(
        dealId: 1,
        source: 'home_feed',
        position: 0,
        child: Container(width: 100, height: 100, color: Colors.blue),
      ),
    ));
    await tester.pump();
    VisibilityDetectorController.instance.notifyNow();
    await tester.pump();

    expect(_hasImpression(analytics, 1), isFalse);

    await tester.pump(const Duration(seconds: 1));

    expect(_hasImpression(analytics, 1), isTrue);

    analytics.onClose(); // cancels the 15s batch-flush Timer it started
    Get.reset();
  });

  testWidgets(
      'F-2: does not log an impression if the card is removed before a '
      'full second of visibility', (tester) async {
    Get.testMode = true;
    final analytics = Get.put(AnalyticsService(api: _RecordingApiService()));

    await tester.pumpWidget(MaterialApp(
      home: ImpressionTracker(
        dealId: 2,
        source: 'home_feed',
        position: 0,
        child: Container(width: 100, height: 100, color: Colors.blue),
      ),
    ));
    await tester.pump();
    VisibilityDetectorController.instance.notifyNow();
    await tester.pump(const Duration(milliseconds: 300));

    // Gone from the tree well before the 1-second mark.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 1));

    expect(_hasImpression(analytics, 2), isFalse);

    analytics.onClose(); // cancels the 15s batch-flush Timer it started
    Get.reset();
  });
}
