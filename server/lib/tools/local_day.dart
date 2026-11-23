/// Household-local calendar days for the tools.
///
/// `occurredOn` is a household-local date (DATA_MODEL 1), so "today",
/// "this month" and date ranges must be computed in the household's time
/// zone. The server has no time-zone database, so this knows the fixed UTC
/// offsets of the zones the app supports today. All of them have no daylight
/// saving time. An unknown zone falls back to Baghdad, the documented default
/// (DATA_MODEL 2.2), which is correct for every current household.
library;

import 'package:clock/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

const _offsets = <String, Duration>{
  'Asia/Baghdad': Duration(hours: 3),
  'Asia/Riyadh': Duration(hours: 3),
  'Asia/Kuwait': Duration(hours: 3),
  'Asia/Qatar': Duration(hours: 3),
  'Asia/Amman': Duration(hours: 3),
  'Europe/Istanbul': Duration(hours: 3),
  'Asia/Dubai': Duration(hours: 4),
  'Asia/Tehran': Duration(hours: 3, minutes: 30),
  'UTC': Duration.zero,
  'Etc/UTC': Duration.zero,
};

/// Whether [timeZone] has a known fixed offset.
bool isKnownTimeZone(String timeZone) => _offsets.containsKey(timeZone);

/// The household-local wall time now, as a UTC-flagged [DateTime] whose
/// fields read as local time (the form `ParseContext.clock` expects).
DateTime localNow(Clock clock, String timeZone) =>
    clock.now().toUtc().add(_offsets[timeZone] ?? _offsets['Asia/Baghdad']!);

/// A clock that reads household-local wall time, for the fast parser.
Clock localClock(Clock clock, String timeZone) =>
    Clock(() => localNow(clock, timeZone));

/// Today's household-local date.
LocalDate localToday(Clock clock, String timeZone) =>
    LocalDate.fromDateTime(localNow(clock, timeZone));

/// `YYYY-MM-DD` of a calendar date.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parses `YYYY-MM-DD` into a UTC midnight, or null.
DateTime? parseIsoDay(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final d = DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
  // Reject rollovers such as 2026-02-31.
  return isoDay(d) == s ? d : null;
}

/// Shifts `YYYY-MM-DD` by [days].
String addDays(String day, int days) =>
    isoDay(parseIsoDay(day)!.add(Duration(days: days)));
