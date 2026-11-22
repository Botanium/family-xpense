/// The household-local date from an IANA time zone name.
///
/// The server has no time-zone database (no `timezone` package), so this
/// knows the fixed offsets of the zones the app is used in today; none of
/// them has daylight saving time. An unknown zone falls back to
/// [defaultZone] and is reported so it can be added.
library;

import 'package:xpense_agent/decide/question_set.dart';

/// The household default (DATA_MODEL 2.2).
const String defaultZone = 'Asia/Baghdad';

/// UTC offsets in minutes, for zones without daylight saving time.
const Map<String, int> fixedOffsets = {
  'Asia/Baghdad': 180,
  'Asia/Kuwait': 180,
  'Asia/Riyadh': 180,
  'Asia/Qatar': 180,
  'Asia/Bahrain': 180,
  'Asia/Amman': 180,
  'Asia/Damascus': 180,
  'Europe/Istanbul': 180,
  'Asia/Dubai': 240,
  'Asia/Muscat': 240,
  'Asia/Tehran': 210,
  'UTC': 0,
  'Etc/UTC': 0,
  'GMT': 0,
};

/// The local day in [tz] at [now], and whether [tz] was known.
({LocalDay day, bool known}) localDay(String tz, DateTime now) {
  final offset = fixedOffsets[tz];
  final local = now.toUtc().add(
    Duration(minutes: offset ?? fixedOffsets[defaultZone]!),
  );
  return (
    day: (year: local.year, month: local.month, day: local.day),
    known: offset != null,
  );
}
