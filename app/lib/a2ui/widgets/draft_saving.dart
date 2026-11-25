/// Saving drafts from a smart component, shared by `EntryList` and
/// `ReceiptSummary`: one save through [XpenseActions], the saved state kept
/// in the surface's own paths (`/ui/status`, `/ui/saved`), and Undo for
/// [XpMotion.toastLifetime].
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/xpense_actions.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Read and write access to a surface's data model, for components that
/// keep their own state in it. Null in widget tests without a surface.
final class SurfaceStore {
  /// Creates a store.
  const new({required this.read, required this.write});

  /// Reads a path.
  final Object? Function(String path) read;

  /// Writes a path.
  final void Function(String path, Object? value) write;
}

/// How many of a card's drafts were saved in the manual form while others
/// stayed on it: a receipt then keeps its groups as they are, since
/// regrouping would bring the saved ones back.
const String formSavedPath = '/ui/formSaved';

/// The count at [formSavedPath].
int formSaves(SurfaceStore? store) => switch (store?.read(formSavedPath)) {
  final num n => n.toInt(),
  true => 1,
  _ => 0,
};

/// What a save produced, as kept at `/ui/saved`.
final class SaveRecord {
  /// Creates a record.
  const new({
    required this.groupId,
    required this.txnIds,
    required this.savedAt,
    this.budgets = const {},
  });

  /// Reads a record from the data model.
  static SaveRecord? tryParse(Object? json) {
    if (json is! Map) return null;
    final group = json['groupId'];
    final at = DateTime.tryParse('${json['savedAt']}');
    if (group is! String || at == null) return null;
    final budgets = <String, BudgetStanding>{};
    if (json['budgets'] case final Map<Object?, Object?> raw) {
      for (final MapEntry(:key, :value) in raw.entries) {
        if (value case {
          'spentMinor': final int spent,
          'limitMinor': final int limit,
          'currency': final String currency,
        }) {
          budgets['$key'] = BudgetStanding(
            spentMinor: spent,
            limitMinor: limit,
            currency: currency,
          );
        }
      }
    }
    return SaveRecord(
      groupId: group,
      txnIds: [
        for (final id in json['txnIds'] as List? ?? const [])
          if (id is String) id,
      ],
      savedAt: at,
      budgets: budgets,
    );
  }

  /// The save group.
  final String groupId;

  /// The transactions written.
  final List<String> txnIds;

  /// When, in UTC.
  final DateTime savedAt;

  /// Budget standings by draft id.
  final Map<String, BudgetStanding> budgets;

  /// The record as the data model keeps it.
  Map<String, Object?> toJson() => {
    'groupId': groupId,
    'txnIds': txnIds,
    'savedAt': savedAt.toIso8601String(),
    if (budgets.isNotEmpty)
      'budgets': {
        for (final MapEntry(:key, :value) in budgets.entries)
          key: {
            'spentMinor': value.spentMinor,
            'limitMinor': value.limitMinor,
            'currency': value.currency,
          },
      },
  };
}

/// Save, undo and the saved state for a smart component's [State].
mixin DraftSaving<T extends StatefulWidget> on State<T> {
  /// The app.
  XpenseActions get saveActions;

  /// The surface the drafts belong to.
  String get saveSurfaceId;

  /// Where the saved state is kept.
  SurfaceStore? get saveStore;

  /// The status the agent set (`review` or `saved`).
  String get initialStatus;

  /// Whether a save is running.
  bool saving = false;

  /// The last save, while the drafts stand saved.
  SaveRecord? saved;

  /// Why the last save failed, until the next attempt.
  SaveFailure? failure;

  /// Whether the agent marked the drafts saved without a local record.
  bool savedElsewhere = false;

  /// Whether an undo is running.
  bool undoing = false;

  /// Whether the last undo failed; Undo stays offered so it can be retried.
  bool undoFailed = false;

  Timer? _undoTimer;

  /// Whether Undo is offered: for [XpMotion.toastLifetime] after a save,
  /// and for as long as a failed undo needs retrying.
  bool get canUndo {
    final record = saved;
    return record != null &&
        (undoFailed ||
            clock.now().toUtc().difference(record.savedAt) <
                XpMotion.toastLifetime);
  }

  /// Restores the saved state from the data model. Call from initState.
  void restoreSaveState() {
    final status = saveStore?.read(SurfacePaths.status) ?? initialStatus;
    saved = SaveRecord.tryParse(saveStore?.read(SurfacePaths.saved));
    savedElsewhere = status == 'saved' && saved == null;
    _scheduleUndoExpiry();
  }

  /// Whether the drafts stand saved.
  bool get isSaved => saved != null || savedElsewhere;

  /// Saves [drafts], then records the outcome; [announce] is read out
  /// politely when it succeeds. Returns whether it did.
  ///
  /// A save that succeeds is recorded in the surface's data model even if
  /// the component was disposed meanwhile, so remounting the surface shows
  /// it saved and never offers to save the same drafts again.
  Future<bool> saveDrafts(
    List<EntryDraft> drafts, {
    required String announce,
    List<DraftCorrection> corrections = const [],
  }) async {
    if (saving || drafts.isEmpty) return false;
    final store = saveStore;
    final actions = saveActions;
    final surfaceId = saveSurfaceId;
    setState(() {
      saving = true;
      failure = null;
    });
    final SaveOutcome outcome;
    try {
      outcome = await actions.saveDrafts(surfaceId, drafts);
    } on Object catch (error, stack) {
      _report(error, stack);
      if (mounted) {
        setState(() {
          saving = false;
          failure = SaveFailure.unknown;
        });
      }
      return false;
    }
    switch (outcome) {
      case DraftsSaved(:final groupId, :final txnIds, :final budgets):
        for (final correction in corrections) {
          unawaited(actions.learn(correction).catchError(_report));
        }
        _recordSaved(
          SaveRecord(
            groupId: groupId,
            txnIds: txnIds,
            savedAt: clock.now().toUtc(),
            budgets: budgets,
          ),
          store,
          announce: announce,
        );
        return true;
      case SaveFailed(:final reason):
        if (!mounted) return false;
        unawaited(XpHaptics.warning());
        setState(() {
          saving = false;
          failure = reason;
        });
        return false;
    }
  }

  /// Records [record] as the drafts' save, in the data model first (it
  /// outlives this component), then on screen.
  void _recordSaved(
    SaveRecord record,
    SurfaceStore? store, {
    required String announce,
  }) {
    store?.write(SurfacePaths.saved, record.toJson());
    store?.write(SurfacePaths.status, 'saved');
    if (!mounted) return;
    setState(() {
      saving = false;
      saved = record;
    });
    _scheduleUndoExpiry();
    unawaited(XpHaptics.saved());
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        announce,
        Directionality.of(context),
      ),
    );
  }

  /// Opens [raw], one of the drafts, in the manual form ("Fix it in the
  /// form"). A save there is this card's save, so nothing is saved twice
  /// (Codex review, PR #46): the draft leaves the card, read again with
  /// [current] once the form closes, through [write]; the last one leaves
  /// the card saved as the form saved it, with Undo. Closing the form
  /// unsaved changes nothing.
  ///
  /// The form's own Undo toast (a draft that leaves others on the card)
  /// undoes through [saveActions], so the agent stops hearing it was
  /// saved, and puts the draft back where it was. A card saved meanwhile
  /// keeps its drafts as saved: the undone one is not put back.
  Future<void> openInForm(
    Object? raw, {
    required List<Object?> Function() current,
    required ValueChanged<List<Object?>>? write,
    required String announce,
  }) async {
    if (saving || isSaved) return;
    final store = saveStore;
    final draft = raw is Map
        ? Map<String, Object?>.from(raw)
        : <String, Object?>{};
    final id = draft['id'];
    bool same(Object? d) =>
        id is String ? d is Map && d['id'] == id : identical(d, raw);
    // The card's last draft: the card then shows the save and its Undo,
    // so the form shows none (one Undo, never two).
    final before = current();
    final last = before.every(same);
    final at = before.indexWhere(same);
    final actions = saveActions;

    Future<void> undo(String groupId) async {
      try {
        await actions.undoSave(groupId);
      } on Object catch (error, stack) {
        _report(error, stack);
        return;
      }
      final left = formSaves(store) - 1;
      store?.write(formSavedPath, left > 0 ? left : null);
      final now = current();
      if (isSaved || now.any(same)) return;
      final i = at.clamp(0, now.length);
      write?.call([...now.take(i), raw, ...now.skip(i)]);
      if (mounted) setState(() {});
    }

    final result = await actions.openManualForm(
      draft,
      surfaceId: saveSurfaceId,
      quiet: last,
      undo: last ? null : undo,
    );
    if (result == null) return;
    final drafts = current();
    final rest = [
      for (final d in drafts)
        if (!same(d)) d,
    ];
    if (rest.isNotEmpty) {
      store?.write(formSavedPath, formSaves(store) + 1);
      write?.call(rest);
      return;
    }
    // The card shows what was saved, not the draft as it was before, under
    // the card's own id (a draft that did not read is saved as "manual").
    write?.call([
      {...result.draft.toJson(), 'id': ?(id is String ? id : null)},
    ]);
    _recordSaved(
      SaveRecord(
        groupId: result.groupId,
        txnIds: result.txnIds,
        savedAt: clock.now().toUtc(),
      ),
      store,
      announce: announce,
    );
  }

  /// Undoes the last save and returns the drafts to review. The saved state
  /// is kept until the app confirms the deletion; if it fails, the drafts
  /// stay saved and Undo stays offered for a retry.
  Future<void> undoSave() async {
    final record = saved;
    if (record == null || undoing) return;
    final store = saveStore;
    final actions = saveActions;
    setState(() {
      undoing = true;
      undoFailed = false;
    });
    try {
      await actions.undoSave(record.groupId);
    } on Object catch (error, stack) {
      _report(error, stack);
      if (mounted) {
        unawaited(XpHaptics.warning());
        setState(() {
          undoing = false;
          undoFailed = true;
        });
      }
      return;
    }
    store?.write(SurfacePaths.saved, null);
    store?.write(SurfacePaths.status, 'review');
    if (!mounted) return;
    _undoTimer?.cancel();
    setState(() {
      undoing = false;
      saved = null;
      savedElsewhere = false;
    });
  }

  void _scheduleUndoExpiry() {
    _undoTimer?.cancel();
    final record = saved;
    if (record == null) return;
    final left =
        XpMotion.toastLifetime - clock.now().toUtc().difference(record.savedAt);
    if (left <= Duration.zero) return;
    _undoTimer = Timer(left, () {
      if (mounted) setState(() {});
    });
  }

  void _report(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(exception: error, stack: stack, library: 'xpense a2ui'),
  );

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }
}
