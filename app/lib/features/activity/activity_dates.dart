// Calendar-day arithmetic for Activity, in plain Dart (no Flutter), so a
// test can run it in a process with another time zone.

/// Whole calendar days from [day] (`YYYY-MM-DD`) to the date of [today]:
/// 0 for today, 1 for yesterday. Null when [day] is malformed.
///
/// Compares dates, never elapsed local time: across a daylight-saving
/// change a local day lasts 23 or 25 hours, so subtracting local midnights
/// would call yesterday "today" (Codex review, PR #38).
int? daysBefore(String day, DateTime today) {
  final date = DateTime.tryParse(day);
  if (date == null) return null;
  return DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
}

/// The `YYYY-MM-DD` of the local date [days] calendar days before [today].
String dayBefore(DateTime today, int days) {
  final d = DateTime.utc(today.year, today.month, today.day - days);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
}
