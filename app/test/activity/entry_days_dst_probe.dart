// Run by entry_days_test.dart in a process whose TZ is America/New_York
// (`flutter test` cannot change its own time zone). Prints one JSON line;
// plain Dart, no Flutter.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:xpense_app/features/activity/detail/entry_days.dart';

void main() {
  // Early on the first day of daylight saving time (2026-03-09 local; the
  // clocks went forward on the 8th, so the local day before lasted 23
  // hours): an entry from the evening before is "Yesterday".
  final now = DateTime(2026, 3, 9, 9);
  print(
    jsonEncode({
      'localDayHours': DateTime(
        2026,
        3,
        9,
      ).difference(DateTime(2026, 3, 8)).inHours,
      'lastNight': entryDaysAgo(DateTime(2026, 3, 8, 20), now),
      'thisMorning': entryDaysAgo(DateTime(2026, 3, 9, 0, 30), now),
      'twoDaysAgo': entryDaysAgo(DateTime(2026, 3, 7, 23), now),
      // A UTC instant reads in local time: 01:00 UTC on the 9th is the
      // evening of the 8th in New York.
      'utcLastNight': entryDaysAgo(DateTime.utc(2026, 3, 9, 1), now),
      // The autumn change: the local day before lasted 25 hours.
      'autumnYesterday': entryDaysAgo(
        DateTime(2026, 11, 1, 0, 30),
        DateTime(2026, 11, 2, 23, 30),
      ),
    }),
  );
}
