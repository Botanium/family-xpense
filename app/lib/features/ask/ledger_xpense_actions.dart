import 'package:flutter/foundation.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// [XpenseActions] whose saves go through the transaction write path
/// (WP-20, `TransactionsRepository.saveEntries`): one batch per card, all
/// or nothing. The household comes from [readHousehold]; the daily rate is
/// written through [fx] (`fxRates/{day}`); navigation is [inner]'s.
final class LedgerXpenseActions implements XpenseActions {
  /// Saves through [transactions]; reads the household with
  /// [readHousehold] each time; the rest goes to [inner].
  new({
    required this.inner,
    required this.transactions,
    required this.fx,
    required this.readHousehold,
    this.clock = const Clock(),
  });

  /// Navigation and the rest the write path does not cover.
  final XpenseActions inner;

  /// Where the daily rate is saved.
  final FxRepository fx;

  /// Today, for the rate answered today.
  final Clock clock;

  // The rate the member answered and when, until the household's own rate
  // stream says the same.
  ({String rate, DateTime at})? _answered;

  /// Reads the current household cache.
  final XpenseHousehold Function() readHousehold;

  /// The write path.
  final TransactionsRepository transactions;

  // What each save wrote, by group id, for its Undo.
  final Map<String, SavedEntries> _saved = {};

  @override
  XpenseHousehold get household {
    final h = readHousehold();
    final answered = _answeredToday;
    if (answered == null) return h;
    return XpenseHousehold(
      baseCurrency: h.baseCurrency,
      accounts: h.accounts,
      categories: h.categories,
      people: h.people,
      loans: h.loans,
      goals: h.goals,
      partnerName: h.partnerName,
      latestRate: answered,
      rateEnteredToday: true,
    );
  }

  String? get _answeredToday {
    final a = _answered;
    if (a == null) return null;
    final now = clock.now();
    final sameDay =
        a.at.year == now.year && a.at.month == now.month && a.at.day == now.day;
    return sameDay ? a.rate : null;
  }

  @override
  Future<SaveOutcome> saveDrafts(
    String surfaceId,
    List<EntryDraft> drafts,
  ) async {
    // Once today's rate is entered (here, or by the partner on their
    // phone), a quote made with an older rate is dropped, so the write
    // path prices the entry with the household's rate for its date
    // (WP-24, Codex review PR #42).
    final household = readHousehold();
    final base = household.baseCurrency;
    final priced = _answeredToday == null && !household.rateEnteredToday
        ? drafts
        : [
            for (final d in drafts)
              if (d.fx != null && d.currency != base) withoutFx(d) else d,
          ];
    var batch = priced;
    var result = await transactions.saveEntries(batch);
    // The household's first rate covers today on: an entry dated before it
    // has no rate to use. The rate the member just entered is the only one
    // there is, so it goes on that entry, and only on it: the others keep
    // the rate for their own date. One at a time, as the write path names
    // the first draft it cannot price.
    final answered = _answeredToday;
    final quoted = <String>{};
    while (answered != null) {
      final draftId = switch (result) {
        Err(failure: EntryRateNeeded(:final draftId)) => draftId,
        _ => null,
      };
      if (draftId == null || !quoted.add(draftId)) break;
      batch = [
        for (final d in batch)
          if (d.id == draftId) withFx(d, answered, base) else d,
      ];
      result = await transactions.saveEntries(batch);
    }
    switch (result) {
      case Ok(:final value):
        _saved[value.groupId] = value;
        return DraftsSaved(groupId: value.groupId, txnIds: value.txnIds);
      case Err(:final failure):
        // The code only, never the drafts (they hold amounts and names).
        debugPrint('save refused: ${failure.code}');
        return SaveFailed(saveFailureOf(failure));
    }
  }

  @override
  Future<void> undoSave(String groupId) async {
    final saved = _saved[groupId];
    if (saved == null) throw StateError('no save $groupId to undo');
    final result = await transactions.undoSave(saved);
    if (result case Err(:final failure)) {
      // The surface keeps the entries saved and says the undo failed.
      throw StateError('undo refused: ${failure.code}');
    }
    _saved.remove(groupId);
  }

  @override
  Future<void> learn(DraftCorrection correction) => inner.learn(correction);

  @override
  Future<void> setDailyRate(String pairRate) async {
    final rate = FxRate.parse(FxPair.usdIqd.code, pairRate).valueOrNull;
    if (rate == null) {
      debugPrint('rate not saved: malformed');
      return;
    }
    final result = await fx.setRate(rateDayOf(clock.now()), rate);
    switch (result) {
      case Ok():
        _answered = (rate: rate.rateString, at: clock.now());
      case Err(:final failure):
        // The prompt stays; the slip asks again.
        debugPrint('rate not saved: ${failure.code}');
    }
  }

  @override
  Future<void> setRecurring(String draftId, RecurringMode mode) =>
      inner.setRecurring(draftId, mode);

  @override
  void openTransaction(String txnId) => inner.openTransaction(txnId);

  @override
  void openLoan(String loanId) => inner.openLoan(loanId);

  @override
  void openGoal(String goalId) => inner.openGoal(goalId);

  @override
  void sendText(String message) => inner.sendText(message);

  @override
  void retakeReceipt() => inner.retakeReceipt();

  @override
  void openManualForm(Map<String, Object?> draft) =>
      inner.openManualForm(draft);

  @override
  void retryQueued(String captureId) => inner.retryQueued(captureId);
}

/// What the card says when the write path refuses a save.
@visibleForTesting
SaveFailure saveFailureOf(TransactionsFailure failure) => switch (failure) {
  TransactionsNotAllowed() => SaveFailure.denied,
  EntryRateNeeded() => SaveFailure.rateNeeded,
  EntryInvalid() || TooManyEntries() => SaveFailure.invalid,
  TransactionNotFound() ||
  TransactionDeleted() ||
  TransactionNotDeleted() ||
  TransactionConflict() ||
  TransactionsUnknown() => SaveFailure.unknown,
};

/// [draft] without its exchange-rate quote.
@visibleForTesting
EntryDraft withoutFx(EntryDraft draft) =>
    EntryDraft.fromJson({...draft.toJson()}..remove('fx'));

/// [draft] quoted at [pairRate] (USD/IQD) into [base]; unchanged when the
/// amount cannot be converted.
@visibleForTesting
EntryDraft withFx(EntryDraft draft, String pairRate, String base) {
  final minor = draft.amountMinor;
  final from = Currency.tryParse(draft.currency ?? '');
  final to = Currency.tryParse(base);
  final rate = FxRate.parse(FxPair.usdIqd.code, pairRate).valueOrNull;
  if (minor == null || from == null || to == null || rate == null) {
    return draft;
  }
  final converted = toBaseAmount(Money(minor, from), to, rate: rate);
  if (converted case Ok(:final value)) {
    return EntryDraft.fromJson({
      ...draft.toJson(),
      'fx': FxQuote(
        pair: FxPair.usdIqd.code,
        pairRate: rate.rateString,
        baseAmountMinor: value.minorUnits,
      ).toJson(),
    });
  }
  return draft;
}
