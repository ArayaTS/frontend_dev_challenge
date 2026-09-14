import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/fake_api_service.dart';

class _RecordingApiService extends FakeApiService {
  final batches = <List<Map<String, dynamic>>>[];

  @override
  Future<void> sendAnalyticsBatch(List<Map<String, dynamic>> events) async {
    batches.add(events);
  }
}

void main() {
  test('F-2: at most one deal_impression per deal per session', () {
    final api = _RecordingApiService();
    final analytics = AnalyticsService(api: api);

    analytics.logImpression(dealId: 7, source: 'home_feed', position: 0);
    analytics.logImpression(dealId: 7, source: 'search', position: 3);
    analytics.logImpression(dealId: 7, source: 'home_feed', position: 0);

    final impressions =
        analytics.events.where((e) => e.name == 'deal_impression').toList();
    expect(impressions.length, 1);
    expect(impressions.single.properties['deal_id'], 7);
    // The first call wins; later calls for the same deal are no-ops.
    expect(impressions.single.properties['source'], 'home_feed');
  });

  test('F-2: impression properties carry deal_id, source and position', () {
    final api = _RecordingApiService();
    final analytics = AnalyticsService(api: api);

    analytics.logImpression(dealId: 42, source: 'flash_rail', position: 2);

    final event =
        analytics.events.singleWhere((e) => e.name == 'deal_impression');
    expect(event.properties, {
      'deal_id': 42,
      'source': 'flash_rail',
      'position': 2,
    });
  });

  test('F-2: batches flush once 10 impressions have accumulated', () async {
    final api = _RecordingApiService();
    final analytics = AnalyticsService(api: api);

    for (var id = 1; id <= 10; id++) {
      analytics.logImpression(dealId: id, source: 'home_feed', position: id);
    }
    // sendAnalyticsBatch is itself async (simulated latency) — let it settle.
    await Future<void>.delayed(Duration.zero);

    expect(api.batches, hasLength(1));
    expect(api.batches.single, hasLength(10));

    // An 11th impression starts a fresh batch, not sent yet.
    analytics.logImpression(dealId: 11, source: 'home_feed', position: 11);
    await Future<void>.delayed(Duration.zero);
    expect(api.batches, hasLength(1));
  });

  test(
      'F-2: a batch flushes 15s (here: overridden) after its first unsent '
      'event, even under 10 events', () async {
    final api = _RecordingApiService();
    final analytics = AnalyticsService(
      api: api,
      batchInterval: const Duration(milliseconds: 30),
    );

    analytics.logImpression(dealId: 1, source: 'home_feed', position: 0);
    expect(api.batches, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(api.batches, hasLength(1));
    expect(api.batches.single, hasLength(1));
  });
}
