// Calendar days between an entry's time and now, in plain Dart (no
// Flutter), so a test can run it in a process with another time zone.
import 'package:xpense_app/features/activity/activity_dates.dart';

/// Whole calendar days from the local date of [at] to the local date of
/// [now]: 0 for today, 1 for yesterday.
///
/// Compares dates ([daysBefore]), never elapsed local time: across a
/// daylight-saving change a local day lasts 23 or 25 hours (Codex review,
/// PR #39).
int entryDaysAgo(DateTime at, DateTime now) {
  final local = at.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final day =
      '${local.year.toString().padLeft(4, '0')}-'
      '${two(local.month)}-${two(local.day)}';
  return daysBefore(day, now.toLocal())!;
}
