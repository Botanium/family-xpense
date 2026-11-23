// Run by activity_dates_test.dart in a process whose TZ is
// America/New_York (`flutter test` cannot change its own time zone).
// Prints one JSON line; plain Dart, no Flutter.
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:xpense_app/features/activity/activity_dates.dart';

void main() {
  // Just after midnight on the first day of daylight saving time: the
  // local day before lasted 23 hours.
  final now = DateTime(2026, 3, 9, 0, 30);
  print(
    jsonEncode({
      'localDayHours': DateTime(
        2026,
        3,
        9,
      ).difference(DateTime(2026, 3, 8)).inHours,
      'yesterday': daysBefore('2026-03-08', now),
      'today': daysBefore('2026-03-09', now),
      'autumnYesterday': daysBefore('2026-11-01', DateTime(2026, 11, 2, 0, 30)),
      'dayBefore1': dayBefore(now, 1),
      'dayBefore2': dayBefore(now, 2),
    }),
  );
}
