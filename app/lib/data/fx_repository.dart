// The household's daily USD/IQD rate (DATA_MODEL 2.13, ARCHITECTURE 3.5,
// D-16): the rates the members entered, one document per household-local
// day under `households/{hid}/fxRates/{yyyy-mm-dd}`, and the household's
// label for them (`official` or `market`).
//
// There is no rate feed. A member answers the daily prompt on Home, the
// inline ask on a slip or the manual form, or edits a day in Settings. A
// conversion on a day uses that day's rate, else the most recent earlier
// one. Editing a day never rewrites saved transactions: each keeps the rate
// it was saved with (DATA_MODEL 1).
//
// This file is the interface features import. The Firestore adapter is
// `fx_repository_firebase.dart` and the in-memory one is
// `fx_repository_fake.dart`; only the composition root and tests name them.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/data/write/ledger_transactions_repository.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The household's label for the rate it enters (`households.rateKind`).
enum RateKind {
  /// The official (central bank) rate.
  official('official'),

  /// The market rate, the default.
  market('market');

  new(this.wire);

  /// The stored string.
  final String wire;

  /// Reads a stored label; anything unknown is [market], the default.
  static RateKind fromWire(Object? value) =>
      value == official.wire ? official : market;
}

/// One day's rate as a member entered it (`fxRates/{day}`).
@immutable
final class DailyRate {
  /// Creates the record.
  const new({
    required this.day,
    required this.rate,
    this.kind = RateKind.market,
    this.enteredBy,
  });

  /// The household-local day, `YYYY-MM-DD`.
  final String day;

  /// Dinars per dollar.
  final FxRate rate;

  /// The label the household gave its rate when this one was entered.
  final RateKind kind;

  /// The uid of the member who entered it, when known.
  final String? enteredBy;

  @override
  bool operator ==(Object other) =>
      other is DailyRate &&
      other.day == day &&
      other.rate == rate &&
      other.kind == kind &&
      other.enteredBy == enteredBy;

  @override
  int get hashCode => Object.hash(day, rate, kind, enteredBy);

  @override
  String toString() => 'DailyRate($day, ${rate.rateString}, ${kind.wire})';
}

/// Why a rate write did not work. Carries a stable [code], never a
/// user-facing string.
@immutable
sealed class FxFailure implements Failure {
  const new();

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => code;
}

/// Not in a household, or Firestore's rules refused the write.
final class FxNotAllowed extends FxFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'fx.not_allowed';
}

/// The day is not a `YYYY-MM-DD` date.
final class FxBadDay extends FxFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'fx.bad_day';
}

/// Anything else; [detail] is for logs.
final class FxUnknown extends FxFailure {
  /// Creates the failure with a machine-readable [detail].
  const new(this.detail);

  /// The error code or type. Never shown.
  final String detail;

  @override
  String get code => 'fx.unknown';
}

/// Reads and writes the household's daily rates.
///
/// Writes are batches that work offline and return once Firestore has them
/// or once they are queued on the phone. Every call returns a [Result].
abstract interface class FxRepository {
  /// The rates of the last [rateHistoryWindow], newest first. Empty while
  /// not in a household.
  Stream<List<DailyRate>> watchRates();

  /// The household's label for its rate.
  Stream<RateKind> watchRateKind();

  /// Saves [rate] as day [day]'s rate, labelled with the household's
  /// current [RateKind], as the signed-in member. Replaces a rate already
  /// entered for that day; saved transactions keep theirs.
  Future<Result<void, FxFailure>> setRate(String day, FxRate rate);

  /// Changes the household's label for the rates entered from now on.
  Future<Result<void, FxFailure>> setRateKind(RateKind kind);
}

/// How far back the rate history goes.
const Duration rateHistoryWindow = Duration(days: 400);

/// How far back the latest rate is looked for. Older rates are stale enough
/// that a form asks for today's instead (WP-13).
const Duration latestRateWindow = Duration(days: 120);

/// How far a typed rate may move from the previous one, in percent, before
/// the app asks "are you sure?" (ARCHITECTURE 3.5, R-07).
const int rateJumpPercent = 5;

final _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Whether [day] is a `YYYY-MM-DD` date.
bool isRateDay(String day) =>
    _dayPattern.hasMatch(day) && DateTime.tryParse(day) != null;

/// The rate a conversion on [day] uses: that day's, else the most recent
/// earlier one (DATA_MODEL 2.13). [newestFirst] is as [FxRepository.
/// watchRates] gives it.
DailyRate? rateOnOrBefore(List<DailyRate> newestFirst, String day) {
  for (final r in newestFirst) {
    if (r.day.compareTo(day) <= 0) return r;
  }
  return null;
}

/// The rate before [day]: the one "Same" keeps.
DailyRate? rateBefore(List<DailyRate> newestFirst, String day) {
  for (final r in newestFirst) {
    if (r.day.compareTo(day) < 0) return r;
  }
  return null;
}

/// Whether [next] is more than [rateJumpPercent] away from [previous], so
/// the app asks for confirmation before saving it (a typo guard).
///
/// Compared exactly in integers: both rates price 10,000 dollars in whole
/// dinars, which is exact for rates with up to four decimals (the keypad's
/// limit).
bool isRateJump(FxRate previous, FxRate next) {
  final p = _scaled(previous);
  final n = _scaled(next);
  if (p == null || n == null || p == 0) return false;
  return (n - p).abs() * 100 > p * rateJumpPercent;
}

int? _scaled(FxRate rate) => rate
    .convert(const Money(1000000, Currency.usd), Currency.iqd)
    .valueOrNull
    ?.minorUnits;

/// What the daily prompt on Home asks: [previous] is the rate "Same" keeps
/// (null for the household's first rate).
@immutable
final class DailyRateAsk {
  /// Creates the ask.
  const new({required this.today, this.previous});

  /// The household-local day being asked for.
  final String today;

  /// The most recent rate before [today].
  final DailyRate? previous;

  @override
  bool operator ==(Object other) =>
      other is DailyRateAsk &&
      other.today == today &&
      other.previous == previous;

  @override
  int get hashCode => Object.hash(today, previous);
}

/// The daily prompt for [today], or null when Home should not ask: the
/// household holds accounts in only one currency, or someone (this member
/// or the partner) already entered today's rate, which covers both
/// (ARCHITECTURE 3.5).
DailyRateAsk? dailyRateAsk({
  required String today,
  required List<DailyRate> rates,
  required Iterable<Currency> accountCurrencies,
}) {
  final currencies = accountCurrencies.toSet();
  if (!currencies.contains(Currency.usd) ||
      !currencies.contains(Currency.iqd)) {
    return null;
  }
  if (rates.any((r) => r.day == today)) return null;
  return DailyRateAsk(today: today, previous: rateBefore(rates, today));
}

/// The household-local day of [now], `YYYY-MM-DD`.
String rateDayOf(DateTime now) => householdDay(now);

/// Today's household-local day, `YYYY-MM-DD`, by the injected clock. It
/// moves on by itself at local midnight, so a screen left open overnight
/// asks for the new day's rate (Codex review, PR #42);
/// [RateDayNotifier.refresh] reads the clock again on demand.
final NotifierProvider<RateDayNotifier, String> rateTodayProvider =
    NotifierProvider<RateDayNotifier, String>(
      RateDayNotifier.new,
      name: 'rateTodayProvider',
    );

/// Holds [rateTodayProvider]'s day and rolls it over.
class RateDayNotifier extends Notifier<String> {
  Timer? _midnight;

  @override
  String build() {
    ref.onDispose(() => _midnight?.cancel());
    return _read();
  }

  /// Reads the clock again; changes the day only if it moved.
  void refresh() {
    final next = _read();
    if (next != state) state = next;
  }

  String _read() {
    final now = ref.read(clockProvider).now();
    _midnight?.cancel();
    final local = now.toLocal();
    final nextDay = DateTime(local.year, local.month, local.day + 1);
    // Should it fire a moment early, the day has not changed and the next
    // timer is set again.
    _midnight = Timer(nextDay.difference(local), refresh);
    return rateDayOf(now);
  }
}

/// The [FxRepository] for this run. Throws until the composition root sets
/// it.
final fxRepositoryProvider = Provider<FxRepository>(
  (ref) =>
      throw UnimplementedError('fxRepositoryProvider is set in bootstrap()'),
  name: 'fxRepositoryProvider',
);

/// The household's rates, newest first, as a stream.
final fxRatesProvider = StreamProvider<List<DailyRate>>(
  (ref) => ref.watch(fxRepositoryProvider).watchRates(),
  name: 'fxRatesProvider',
);

/// The household's label for its rate.
final rateKindProvider = StreamProvider<RateKind>(
  (ref) => ref.watch(fxRepositoryProvider).watchRateKind(),
  name: 'rateKindProvider',
);

/// The most recent rate of the last [latestRateWindow], or null when the
/// household has none.
final Provider<AsyncValue<DailyRate?>> latestDailyRateProvider =
    Provider<AsyncValue<DailyRate?>>((ref) {
      final rates = ref.watch(fxRatesProvider);
      // Recomputed when the day moves on, so the window moves with it.
      ref.watch(rateTodayProvider);
      final from = rateDayOf(
        ref.read(clockProvider).now().subtract(latestRateWindow),
      );
      return rates.whenData(
        (list) => list.where((r) => r.day.compareTo(from) >= 0).firstOrNull,
      );
    }, name: 'latestDailyRateProvider');

/// The household's latest USD/IQD rate (see [latestDailyRateProvider]).
final Provider<AsyncValue<FxRate?>> latestRateProvider =
    Provider<AsyncValue<FxRate?>>(
      (ref) => ref.watch(latestDailyRateProvider).whenData((r) => r?.rate),
      name: 'latestRateProvider',
    );
