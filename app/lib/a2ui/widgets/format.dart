/// Formatting shared by the Xpense widgets. Money goes through the
/// currency table in `xpense_shared` (never a hard-coded exponent) and the
/// Signal `MoneyFormat`; dates are household-local `YYYY-MM-DD` strings.
library;

import 'package:clock/clock.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The decimal places of [currency], or null for a code the app does not
/// know. An unknown code is never given a default of two.
int? exponentOf(String? currency) =>
    currency == null ? null : Currency.tryParse(currency)?.exponent;

/// [minor] in [currency] as `IQD 10,000`, or null for an unknown currency.
String? moneyLabel(int minor, String? currency, {bool signed = false}) {
  final exponent = exponentOf(currency);
  if (exponent == null) return null;
  return MoneyFormat.figure(
    minor,
    exponent: exponent,
    currency: currency!,
    signed: signed,
  ).withCurrency;
}

/// [minor] in [currency] without the code: `10,000` or `85.00`.
String? figureLabel(int minor, String? currency) {
  final exponent = exponentOf(currency);
  if (exponent == null) return null;
  return MoneyFormat.figure(minor, exponent: exponent).amount;
}

/// The converted line under an amount: `≈ USD 5.87`.
String? approxLabel(BuildContext context, int minor, String? currency) {
  final money = moneyLabel(minor, currency);
  return money == null ? null : context.l10n.a2uiApprox(money);
}

/// Reads an integer from JSON, accepting `1250.0`.
int? intOf(Object? value) => switch (value) {
  final int i => i,
  final double d when d == d.truncateToDouble() && d.isFinite => d.toInt(),
  _ => null,
};

/// Parses a household-local `YYYY-MM-DD` date.
DateTime? dayOf(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// The `YYYY-MM-DD` form of [day].
String dayString(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Today in the household's time zone (the device's, for now).
DateTime today() {
  final now = clock.now();
  return DateTime(now.year, now.month, now.day);
}

/// Yesterday, by the calendar (not 24 hours ago).
DateTime yesterday() {
  final t = today();
  return DateTime(t.year, t.month, t.day - 1);
}

/// A day as people say it: "Today", "Yesterday" or "Nov 20", with the time
/// appended when given.
String dayLabel(BuildContext context, String? value, {String? time}) {
  final l10n = context.l10n;
  final day = dayOf(value);
  if (day == null) return value ?? '';
  final locale = Localizations.localeOf(context).toLanguageTag();
  final date = day == today()
      ? l10n.a2uiDayToday
      : day == yesterday()
      ? l10n.a2uiDayYesterday
      : DateFormat.MMMd(locale).format(day);
  return time == null ? date : l10n.a2uiDayAtTime(date, time);
}

/// A share from 0 to 1 as a whole percentage: `79%`.
String percentLabel(BuildContext context, num share) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return NumberFormat.percentPattern(locale).format(share);
}
