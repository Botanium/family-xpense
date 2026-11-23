import 'package:flutter/foundation.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// [XpenseActions] whose saves go through the transaction write path
/// (WP-20, `TransactionsRepository.saveEntries`): one batch per card, all
/// or nothing. Everything else (the household cache, rates, navigation) is
/// [inner]'s.
final class LedgerXpenseActions implements XpenseActions {
  /// Saves through [transactions]; the rest goes to [inner].
  new({required this.inner, required this.transactions});

  /// The household cache, rates and navigation.
  final XpenseActions inner;

  /// The write path.
  final TransactionsRepository transactions;

  // What each save wrote, by group id, for its Undo.
  final Map<String, SavedEntries> _saved = {};

  @override
  XpenseHousehold get household => inner.household;

  @override
  Future<SaveOutcome> saveDrafts(
    String surfaceId,
    List<EntryDraft> drafts,
  ) async {
    final result = await transactions.saveEntries(drafts);
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
  Future<void> setDailyRate(String pairRate) => inner.setDailyRate(pairRate);

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
  EntryInvalid() ||
  EntryRateNeeded() ||
  TooManyEntries() => SaveFailure.invalid,
  TransactionNotFound() ||
  TransactionDeleted() ||
  TransactionNotDeleted() ||
  TransactionConflict() ||
  TransactionsUnknown() => SaveFailure.unknown,
};
