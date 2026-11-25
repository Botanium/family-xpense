import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/data/rules_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The app's [XpenseActions]: the household cache and the write path.
///
/// Until the transaction write path (WP-20) lands, the composition root
/// sets the in-memory fake from `lib/a2ui/testing/`. Throws until set.
final xpenseActionsProvider = Provider<XpenseActions>(
  (ref) =>
      throw UnimplementedError('xpenseActionsProvider is set in bootstrap()'),
  name: 'xpenseActionsProvider',
);

/// The household's privacy mode (ARCHITECTURE 6). Smart, the product
/// default, until the household settings (Settings, privacy mode) store
/// it; the composition root or a test may override it.
final capturePrivacyModeProvider = Provider<CapturePrivacyMode>(
  (ref) => CapturePrivacyMode.smart,
  name: 'capturePrivacyModeProvider',
);

/// The Ask thread's [XpenseActions]: the app's, plus learning and sending.
///
/// - `learn` turns a corrected guess into a `RuleLesson`. The rule also
///   keeps the account the member saved with, so the next message about the
///   same merchant settles both fields on the phone (story S3.11).
/// - `sendText` starts a capture in this thread.
final class AskActions implements XpenseActions {
  /// Wraps the app's actions.
  new({
    required this._inner,
    required this._rules,
    required this._send,
    this.ruleKinds = const {},
  });

  final XpenseActions _inner;

  /// The rules store, read when a lesson arrives: it changes with the
  /// membership, and the thread must not.
  final RulesRepository Function() _rules;
  final void Function(String text) _send;

  /// The rule kind of each local draft's title, by draft id. Agent drafts
  /// are taught as merchants.
  final Map<String, RuleKind> ruleKinds;

  final Map<String, ({EntryDraft draft, String? txnId})> _saved = {};

  @override
  XpenseHousehold get household => _inner.household;

  @override
  Future<SaveOutcome> saveDrafts(
    String surfaceId,
    List<EntryDraft> drafts,
  ) async {
    final outcome = await _inner.saveDrafts(surfaceId, drafts);
    if (outcome case DraftsSaved(:final txnIds)) {
      for (final (i, d) in drafts.indexed) {
        _saved[d.id] = (draft: d, txnId: i < txnIds.length ? txnIds[i] : null);
      }
    }
    return outcome;
  }

  @override
  Future<void> undoSave(String groupId) => _inner.undoSave(groupId);

  @override
  Future<void> learn(DraftCorrection correction) async {
    final lesson = lessonFor(
      correction,
      saved: _saved[correction.draftId]?.draft,
      txnId: _saved[correction.draftId]?.txnId,
      kind: ruleKinds[correction.draftId] ?? RuleKind.merchant,
    );
    if (lesson == null) return;
    await _rules().learn(lesson);
    await _inner.learn(correction);
  }

  @override
  Future<void> setDailyRate(String pairRate) => _inner.setDailyRate(pairRate);

  @override
  Future<void> setRecurring(String draftId, RecurringMode mode) =>
      _inner.setRecurring(draftId, mode);

  @override
  void openTransaction(String txnId) => _inner.openTransaction(txnId);

  @override
  void openLoan(String loanId) => _inner.openLoan(loanId);

  @override
  void openGoal(String goalId) => _inner.openGoal(goalId);

  @override
  void sendText(String message) => _send(message);

  @override
  void retakeReceipt() => _inner.retakeReceipt();

  @override
  Future<FormSaved?> openManualForm(
    Map<String, Object?> draft, {
    String? surfaceId,
    bool quiet = false,
    Future<void> Function(String groupId)? undo,
  }) => _inner.openManualForm(
    draft,
    surfaceId: surfaceId,
    quiet: quiet,
    undo: undo,
  );

  @override
  Future<void> openAddAccount() => _inner.openAddAccount();

  @override
  void retryQueued(String captureId) => _inner.retryQueued(captureId);
}

/// The rule [correction] teaches, or null when it teaches nothing: no
/// title to key it by, or a field rules do not set.
///
/// The corrected field takes the member's choice. The draft as [saved]
/// adds its account (and, for an account correction, its category), which
/// the member confirmed by saving, so the next identical merchant needs no
/// question at all.
@visibleForTesting
RuleLesson? lessonFor(
  DraftCorrection correction, {
  required RuleKind kind,
  EntryDraft? saved,
  String? txnId,
}) {
  final title = correction.title ?? saved?.title;
  if (title == null || title.trim().isEmpty) return null;
  final chosen = correction.chosen;
  if (chosen is! String || chosen.isEmpty) return null;
  final lesson = switch (correction.field) {
    'categoryId' => RuleLesson(
      kind: kind,
      pattern: title,
      categoryId: chosen,
      accountId: saved?.accountId,
      fromTxnId: txnId,
    ),
    'accountId' => RuleLesson(
      kind: kind,
      pattern: title,
      accountId: chosen,
      categoryId: saved?.categoryId,
      fromTxnId: txnId,
    ),
    'who' => RuleLesson(
      kind: kind,
      pattern: title,
      who: chosen,
      fromTxnId: txnId,
    ),
    'intent' => RuleLesson(
      kind: kind,
      pattern: title,
      intent: chosen,
      fromTxnId: txnId,
    ),
    _ => null,
  };
  return lesson == null || lesson.isEmpty ? null : lesson;
}
