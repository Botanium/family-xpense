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
        final record = SaveRecord(
          groupId: groupId,
          txnIds: txnIds,
          savedAt: clock.now().toUtc(),
          budgets: budgets,
        );
        store?.write(SurfacePaths.saved, record.toJson());
        store?.write(SurfacePaths.status, 'saved');
        for (final correction in corrections) {
          unawaited(actions.learn(correction).catchError(_report));
        }
        if (!mounted) return true;
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
