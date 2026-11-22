/// What the Xpense catalog asks of the app (A2UI_CATALOG 5.1).
///
/// Smart components (`EntryList`, `ReceiptSummary`) and local actions call
/// the app only through [XpenseActions]. The real implementation arrives
/// with the transaction write path (WP-20) and is wired in WP-34; until
/// then `FakeXpenseActions` stands in for tests and the gallery.
///
/// Nothing here depends on `a2ui_core`, so features can implement it.
library;

import 'package:xpense_shared/xpense_shared.dart';

/// An account the member can see.
final class HouseholdAccount {
  /// Creates an account.
  const new({required this.id, required this.name, required this.currency});

  /// Account id.
  final String id;

  /// Display name, such as "Cash".
  final String name;

  /// ISO currency code.
  final String currency;
}

/// A category of the household.
final class HouseholdCategory {
  /// Creates a category.
  const new({required this.id, required this.name, this.colorKey});

  /// Category id.
  final String id;

  /// Display name, such as "Dining out".
  final String name;

  /// Colour key such as `cat3`, for dots.
  final String? colorKey;
}

/// A named thing a draft can point at: a person, a loan or a goal.
final class HouseholdItem {
  /// Creates an item.
  const new({required this.id, required this.name});

  /// Its id.
  final String id;

  /// Its display name.
  final String name;
}

/// The household cache the smart components read: names for display,
/// options for pickers, and the ids every save is checked against.
final class XpenseHousehold {
  /// Creates a snapshot.
  const new({
    required this.baseCurrency,
    this.accounts = const [],
    this.categories = const [],
    this.people = const [],
    this.loans = const [],
    this.goals = const [],
    this.partnerName,
    this.latestRate,
    this.rateEnteredToday = false,
  });

  /// The household base currency, such as `USD`.
  final String baseCurrency;

  /// Accounts, in the household's order.
  final List<HouseholdAccount> accounts;

  /// Categories, in the household's order.
  final List<HouseholdCategory> categories;

  /// Counterparties.
  final List<HouseholdItem> people;

  /// Open loans.
  final List<HouseholdItem> loans;

  /// Goals.
  final List<HouseholdItem> goals;

  /// The partner's first name, for `who: partner`; null before they join.
  final String? partnerName;

  /// The latest USD/IQD rate as a decimal string, such as `"1705"`.
  final String? latestRate;

  /// Whether someone has entered today's rate.
  final bool rateEnteredToday;

  /// The ids a save is checked against.
  HouseholdRefs get refs => HouseholdRefs(
    accountCurrencies: {for (final a in accounts) a.id: a.currency},
    categoryIds: {for (final c in categories) c.id},
    personIds: {for (final p in people) p.id},
    loanIds: {for (final l in loans) l.id},
    goalIds: {for (final g in goals) g.id},
  );

  /// The account with [id], if known.
  HouseholdAccount? account(String? id) =>
      accounts.where((a) => a.id == id).firstOrNull;

  /// The category with [id], if known.
  HouseholdCategory? category(String? id) =>
      categories.where((c) => c.id == id).firstOrNull;

  /// The person with [id], if known.
  HouseholdItem? person(String? id) =>
      people.where((p) => p.id == id).firstOrNull;

  /// The goal with [id], if known.
  HouseholdItem? goal(String? id) => goals.where((g) => g.id == id).firstOrNull;
}

/// Where a saved entry leaves its budget, for the saved line
/// ("SAVED · DINING 85,000 / 120,000").
final class BudgetStanding {
  /// Creates a standing.
  const new({
    required this.spentMinor,
    required this.limitMinor,
    required this.currency,
  });

  /// Spent so far this period, including the new entry.
  final int spentMinor;

  /// The budget limit.
  final int limitMinor;

  /// The budget's currency.
  final String currency;
}

/// The result of [XpenseActions.saveDrafts].
sealed class SaveOutcome {
  const new();
}

/// The drafts were written as one group.
final class DraftsSaved extends SaveOutcome {
  /// Creates the outcome.
  const new({
    required this.groupId,
    required this.txnIds,
    this.budgets = const {},
  });

  /// The save group, for [XpenseActions.undoSave].
  final String groupId;

  /// The new transaction ids, in draft order.
  final List<String> txnIds;

  /// Budget standings by draft id, where the entry falls in a budget.
  final Map<String, BudgetStanding> budgets;
}

/// Why a save did not happen.
enum SaveFailure {
  /// The repository rejected a draft (an id, amount or currency).
  invalid,

  /// The member may not write to that account.
  denied,

  /// Anything else; the drafts stay on screen.
  unknown,
}

/// Nothing was written.
final class SaveFailed extends SaveOutcome {
  /// Creates the outcome.
  const new(this.reason);

  /// Why.
  final SaveFailure reason;
}

/// A guessed field the member changed before saving; becomes a rule
/// (A2UI_CATALOG 5.1, `learn`).
final class DraftCorrection {
  /// Creates a correction.
  const new({
    required this.draftId,
    required this.field,
    required this.guessed,
    required this.chosen,
    this.title,
  });

  /// The draft it came from.
  final String draftId;

  /// The field, such as `categoryId`.
  final String field;

  /// The value the app guessed.
  final Object? guessed;

  /// The value the member chose.
  final Object? chosen;

  /// The draft's merchant or label, the rule's key.
  final String? title;
}

/// How an entry repeats, for [XpenseActions.setRecurring].
enum RecurringMode {
  /// Every month.
  monthly,

  /// Every week.
  weekly,
}

/// The calls the Xpense catalog makes into the app. None of them becomes an
/// agent turn.
abstract interface class XpenseActions {
  /// The household cache, read when a component builds.
  XpenseHousehold get household;

  /// Validates and writes [drafts] from surface [surfaceId] as one group.
  Future<SaveOutcome> saveDrafts(String surfaceId, List<EntryDraft> drafts);

  /// Soft-deletes the group of a save.
  Future<void> undoSave(String groupId);

  /// Upserts a rule from a corrected guess.
  Future<void> learn(DraftCorrection correction);

  /// Saves [pairRate] as today's USD/IQD rate for the household.
  Future<void> setDailyRate(String pairRate);

  /// Creates or updates a recurring template from a saved draft.
  Future<void> setRecurring(String draftId, RecurringMode mode);

  /// Opens a saved transaction.
  void openTransaction(String txnId);

  /// Opens a loan.
  void openLoan(String loanId);

  /// Opens a goal.
  void openGoal(String goalId);

  /// Starts a new capture with [message], through the router.
  void sendText(String message);

  /// Reopens the camera.
  void retakeReceipt();

  /// Opens the manual form prefilled with [draft], as found in the data
  /// model (it may be malformed).
  void openManualForm(Map<String, Object?> draft);

  /// Retries a capture waiting in the offline queue.
  void retryQueued(String captureId);
}
