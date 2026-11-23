// An in-memory `FxRepository` for tests and the `fakes` environment. Only
// the composition root and tests name this file.
import 'dart:async';

import 'package:clock/clock.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// An [FxRepository] that keeps one household's rates in memory.
///
/// With a [ledger] (the in-memory write path's store), every rate entered
/// here is written to it too, so a save prices entries with the rates the
/// app shows, as one Firestore household would.
final class MemoryFxRepository implements FxRepository {
  /// Creates the store for [viewerUid], holding [rates] (any order) and
  /// the rates already in [ledger].
  ///
  /// A `standing` rate reads as entered the day before [clock]'s today,
  /// whatever today is: a household that has a rate and has not been
  /// asked today. It is in [ledger] for the day before the clock's today
  /// at creation.
  new({
    this.viewerUid = 'uid-you',
    Iterable<DailyRate> rates = const [],
    this._kind = RateKind.market,
    this._standing,
    this.ledger,
    Clock? clock,
  }) : clock = clock ?? const Clock() {
    for (final r in ledger?.rates.values ?? const <DayRate>[]) {
      _rates[r.day] = DailyRate(
        day: r.day,
        rate: r.rate,
        kind: RateKind.fromWire(r.kind),
      );
    }
    rates.forEach(_put);
    if (_standing case final standing?) {
      final day = rateDayOf(this.clock.daysAgo(1));
      ledger?.rates.putIfAbsent(
        day,
        () => DayRate(day: day, rate: standing, kind: _kind.wire),
      );
    }
  }

  /// Today, for the `standing` rate and the history window. The
  /// composition root sets it to the app's clock.
  Clock clock;

  FxRate? _standing;

  /// Who [setRate] enters rates as.
  String viewerUid;

  /// The write path's store this one keeps in step.
  final MemoryLedgerStore? ledger;

  final Map<String, DailyRate> _rates = {};
  RateKind _kind;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// When set, the next write fails with it (then it clears).
  FxFailure? nextFailure;

  /// Every rate written through [setRate], in order.
  final List<DailyRate> written = [];

  /// The rates, newest first.
  List<DailyRate> get rates {
    final all = {..._rates};
    if (_standing case final standing?) {
      final day = rateDayOf(clock.daysAgo(1));
      all.putIfAbsent(
        day,
        () => DailyRate(day: day, rate: standing, kind: _kind),
      );
    }
    return all.values.toList()..sort((a, b) => b.day.compareTo(a.day));
  }

  /// The newest rate, if any.
  DailyRate? get latest => rates.firstOrNull;

  /// Puts [rate] in the store as its member entered it, without recording
  /// a write: how a test plays the partner's phone.
  void put(DailyRate rate) {
    _put(rate);
    _changes.add(null);
  }

  /// Removes every rate, the standing one too.
  void clear() {
    _rates.clear();
    _standing = null;
    ledger?.rates.clear();
    _changes.add(null);
  }

  void _put(DailyRate rate) {
    _rates[rate.day] = rate;
    ledger?.rates[rate.day] = DayRate(
      day: rate.day,
      rate: rate.rate,
      kind: rate.kind.wire,
    );
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  @override
  Stream<List<DailyRate>> watchRates() => _watch(() {
    final from = rateDayOf(clock.now().subtract(rateHistoryWindow));
    return [
      for (final r in rates)
        if (r.day.compareTo(from) >= 0) r,
    ];
  });

  @override
  Stream<RateKind> watchRateKind() => _watch(() => _kind);

  /// The household's label.
  RateKind get kind => _kind;

  @override
  Future<Result<void, FxFailure>> setRate(String day, FxRate rate) async {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      return Err(failure);
    }
    if (!isRateDay(day) || rate.pair != FxPair.usdIqd) {
      return const Err(FxBadDay());
    }
    final entered = DailyRate(
      day: day,
      rate: rate,
      kind: _kind,
      enteredBy: viewerUid,
    );
    written.add(entered);
    put(entered);
    return const Ok(null);
  }

  @override
  Future<Result<void, FxFailure>> setRateKind(RateKind kind) async {
    final failure = nextFailure;
    if (failure != null) {
      nextFailure = null;
      return Err(failure);
    }
    _kind = kind;
    if (ledger?.householdInfo case final info?) {
      ledger!.householdInfo = LedgerHousehold(
        baseCurrency: info.baseCurrency,
        memberIds: info.memberIds,
        rateKind: kind.wire,
      );
    }
    _changes.add(null);
    return const Ok(null);
  }
}
