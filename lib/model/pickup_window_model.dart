import 'package:intl/intl.dart';

/// A store's pickup window. The API sends instants as ISO-8601 UTC strings.
class PickupWindowModel {
  final DateTime start;
  final DateTime end;

  const PickupWindowModel({required this.start, required this.end});

  factory PickupWindowModel.fromJson(Map<String, dynamic> json) {
    return PickupWindowModel(
      start: DateTime.parse(json['start'] as String? ?? ''),
      end: DateTime.parse(json['end'] as String? ?? ''),
    );
  }

  /// The market this app serves (Asia/Bangkok) has a fixed UTC+7 offset
  /// with no daylight saving. API instants are UTC (see FakeApiService);
  /// wall-clock display and "is this today" must use the market's local
  /// time — not the raw UTC fields, and not the device's own timezone,
  /// which may not be Bangkok's.
  static const _marketUtcOffsetHours = 7;

  DateTime get _marketStart =>
      start.toUtc().add(const Duration(hours: _marketUtcOffsetHours));
  DateTime get _marketEnd =>
      end.toUtc().add(const Duration(hours: _marketUtcOffsetHours));
  static DateTime get _marketNow =>
      DateTime.now().toUtc().add(const Duration(hours: _marketUtcOffsetHours));

  /// Human readable label, e.g. "17:30 – 21:00", in the market's local time.
  String get label =>
      '${DateFormat('HH:mm').format(_marketStart)} – ${DateFormat('HH:mm').format(_marketEnd)}';

  /// Whether pickup starts today, in the market's local time.
  bool get isToday {
    final s = _marketStart;
    final n = _marketNow;
    return s.year == n.year && s.month == n.month && s.day == n.day;
  }

  /// Whether the store is currently accepting pickups.
  bool get isOpenNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  Duration get untilStart => start.difference(DateTime.now());
}
