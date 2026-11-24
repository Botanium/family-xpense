/// A fake [XpenseActions] for tests and the a2ui gallery, until the
/// transaction write path (WP-20) gives the real one (wired in WP-34).
/// It records every call and saves into memory.
library;

import 'dart:async';

import 'package:xpense_app/a2ui/xpense_actions.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The household the fixtures and goldens are written against.
const XpenseHousehold sampleHousehold = XpenseHousehold(
  baseCurrency: 'USD',
  accounts: [
    HouseholdAccount(id: 'acc_chk', name: 'Checking', currency: 'USD'),
    HouseholdAccount(id: 'acc_cash', name: 'Cash', currency: 'IQD'),
    HouseholdAccount(id: 'acc_sav', name: 'Savings', currency: 'USD'),
  ],
  categories: [
    HouseholdCategory(
      id: 'dining',
      name: 'Dining out',
      kind: 'expense',
      colorKey: 'cat1',
    ),
    HouseholdCategory(
      id: 'groceries',
      name: 'Groceries',
      kind: 'expense',
      colorKey: 'cat2',
    ),
    HouseholdCategory(
      id: 'household',
      name: 'Household',
      kind: 'expense',
      colorKey: 'cat3',
    ),
    HouseholdCategory(
      id: 'gifts',
      name: 'Gifts',
      kind: 'expense',
      colorKey: 'cat4',
    ),
    HouseholdCategory(
      id: 'transport',
      name: 'Transport',
      kind: 'expense',
      colorKey: 'cat5',
    ),
    HouseholdCategory(
      id: 'utilities',
      name: 'Utilities',
      kind: 'expense',
      colorKey: 'cat6',
    ),
    HouseholdCategory(
      id: 'rent',
      name: 'Rent',
      kind: 'expense',
      colorKey: 'cat7',
    ),
    HouseholdCategory(
      id: 'salary',
      name: 'Salary',
      kind: 'income',
      colorKey: 'cat8',
    ),
  ],
  people: [HouseholdItem(id: 'p_alex', name: 'Alex')],
  loans: [HouseholdItem(id: 'loan_7', name: 'Alex')],
  goals: [HouseholdItem(id: 'goal_2', name: 'Holiday')],
  partnerName: 'Sam',
  latestRate: '1705',
  rateEnteredToday: true,
);

/// One recorded call.
typedef FakeCall = ({String method, Object? argument});

/// Records calls and keeps saves in memory.
class FakeXpenseActions implements XpenseActions {
  /// Creates the fake over [household].
  new({this.household = sampleHousehold, this.saveResult});

  @override
  XpenseHousehold household;

  /// When set, every save returns this instead of succeeding.
  SaveOutcome? saveResult;

  /// When set, saves wait for it, so a test can see the busy state.
  Completer<void>? saveGate;

  /// When set, every undo throws this, as a failed deletion would.
  Error? undoError;

  /// Every call, in order.
  final List<FakeCall> calls = [];

  /// The drafts of each saved group, by group id; undone groups removed.
  final Map<String, List<EntryDraft>> saved = {};

  /// Budget standings returned with saves, by category id.
  Map<String, BudgetStanding> budgets = const {};

  int _next = 0;

  /// The names of the calls made, in order.
  List<String> get methods => [for (final c in calls) c.method];

  @override
  Future<SaveOutcome> saveDrafts(
    String surfaceId,
    List<EntryDraft> drafts,
  ) async {
    calls.add((method: 'saveDrafts', argument: drafts));
    await saveGate?.future;
    final forced = saveResult;
    if (forced != null) return forced;
    final group = 'grp_${++_next}';
    saved[group] = drafts;
    return DraftsSaved(
      groupId: group,
      txnIds: [for (var i = 0; i < drafts.length; i++) 't_${_next}_$i'],
      budgets: {
        for (final d in drafts)
          if (budgets[d.categoryId] != null) d.id: budgets[d.categoryId]!,
      },
    );
  }

  @override
  Future<void> undoSave(String groupId) async {
    calls.add((method: 'undoSave', argument: groupId));
    final error = undoError;
    if (error != null) throw error;
    saved.remove(groupId);
  }

  @override
  Future<void> learn(DraftCorrection correction) async =>
      calls.add((method: 'learn', argument: correction));

  @override
  Future<void> setDailyRate(String pairRate) async {
    calls.add((method: 'setDailyRate', argument: pairRate));
    household = XpenseHousehold(
      baseCurrency: household.baseCurrency,
      accounts: household.accounts,
      categories: household.categories,
      people: household.people,
      loans: household.loans,
      goals: household.goals,
      partnerName: household.partnerName,
      soleMember: household.soleMember,
      latestRate: pairRate,
      rateEnteredToday: true,
    );
  }

  @override
  Future<void> setRecurring(String draftId, RecurringMode mode) async =>
      calls.add((method: 'setRecurring', argument: (draftId, mode)));

  @override
  void openTransaction(String txnId) =>
      calls.add((method: 'openTransaction', argument: txnId));

  @override
  void openLoan(String loanId) =>
      calls.add((method: 'openLoan', argument: loanId));

  @override
  void openGoal(String goalId) =>
      calls.add((method: 'openGoal', argument: goalId));

  @override
  void sendText(String message) =>
      calls.add((method: 'sendText', argument: message));

  @override
  void retakeReceipt() => calls.add((method: 'retakeReceipt', argument: null));

  @override
  Future<FormSaved?> openManualForm(
    Map<String, Object?> draft, {
    String? surfaceId,
    bool quiet = false,
  }) async {
    calls.add((method: 'openManualForm', argument: draft));
    return manualFormResult?.call(draft);
  }

  /// What the manual form saves for a draft; null closes it unsaved.
  FormSaved? Function(Map<String, Object?> draft)? manualFormResult;

  @override
  Future<void> openAddAccount() async =>
      calls.add((method: 'openAddAccount', argument: null));

  @override
  void retryQueued(String captureId) =>
      calls.add((method: 'retryQueued', argument: captureId));
}
