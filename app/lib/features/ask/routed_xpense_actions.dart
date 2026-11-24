import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The Ask cards' navigation through the app's router: "Fix it in the
/// form" opens Add manually prefilled, "View" opens the entry, and "Add an
/// account" opens the new-account sheet. Everything else goes to [inner].
///
/// Before this, the app passed the in-memory fake for navigation, so these
/// buttons did nothing on a phone (owner's first phone test, 2026-11-24).
final class RoutedXpenseActions implements XpenseActions {
  /// Navigates with [router]; the rest goes to [inner].
  new({required this.router, required this.inner});

  /// The app's router, read when a button is tapped.
  final GoRouter Function() router;

  /// What this does not cover.
  final XpenseActions inner;

  @override
  XpenseHousehold get household => inner.household;

  @override
  Future<SaveOutcome> saveDrafts(String surfaceId, List<EntryDraft> drafts) =>
      inner.saveDrafts(surfaceId, drafts);

  @override
  Future<void> undoSave(String groupId) => inner.undoSave(groupId);

  @override
  Future<void> learn(DraftCorrection correction) => inner.learn(correction);

  @override
  Future<void> setDailyRate(String pairRate) => inner.setDailyRate(pairRate);

  @override
  Future<void> setRecurring(String draftId, RecurringMode mode) =>
      inner.setRecurring(draftId, mode);

  @override
  void openTransaction(String txnId) =>
      unawaited(router().push<void>(AppRoutes.entry(txnId)));

  @override
  void openLoan(String loanId) => inner.openLoan(loanId);

  @override
  void openGoal(String goalId) => inner.openGoal(goalId);

  @override
  void sendText(String message) => inner.sendText(message);

  @override
  void retakeReceipt() => inner.retakeReceipt();

  /// A draft that does not read opens the form empty. What the form saves
  /// comes back, so the card settles its draft (Codex review, PR #46).
  @override
  Future<FormSaved?> openManualForm(
    Map<String, Object?> draft, {
    String? surfaceId,
    bool quiet = false,
  }) async {
    final request = (
      draft: checkDraft(draft, const HouseholdRefs()).draft,
      quiet: quiet,
    );
    final result = await router().push<FormSave>(
      AppRoutes.addEntry,
      extra: request,
    );
    if (result == null) return null;
    return FormSaved(
      groupId: result.saved.groupId,
      txnIds: result.saved.txnIds,
      draft: result.draft,
    );
  }

  @override
  Future<void> openAddAccount() => router().push<void>(AppRoutes.addAccount);

  @override
  void retryQueued(String captureId) => inner.retryQueued(captureId);
}
