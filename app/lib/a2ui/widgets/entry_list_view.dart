import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/draft_fields.dart';
import 'package:xpense_app/a2ui/widgets/draft_saving.dart';
import 'package:xpense_app/a2ui/widgets/entry_slip_view.dart';
import 'package:xpense_app/a2ui/xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The catalog `EntryList` (A2UI_CATALOG 3.2): one slip per draft, local
/// editing through pickers, one save for all, Undo for ten seconds, and the
/// recurring offer. Edits write the whole `/drafts` array back through the
/// binding; without a binding the drafts are read-only.
class EntryListView extends StatefulWidget {
  /// Creates the list.
  const new({
    required this.drafts,
    this.title,
    this.initialStatus = 'review',
    this.onDraftsChanged,
    this.store,
    super.key,
  });

  /// The value at `/drafts`, as found (it may hold malformed drafts).
  final List<Object?> drafts;

  /// Heading.
  final String? title;

  /// The status the agent set.
  final String initialStatus;

  /// Writes the drafts back; null makes them read-only.
  final ValueChanged<List<Object?>>? onDraftsChanged;

  /// The surface's data model, for the saved state.
  final SurfaceStore? store;

  @override
  State<EntryListView> createState() => _EntryListViewState();
}

class _EntryListViewState extends State<EntryListView>
    with DraftSaving<EntryListView> {
  /// The guessed values as first shown, by draft id, to learn corrections.
  final Map<String, Map<String, Object?>> _guesses = {};

  /// Drafts whose duplicate hint the member dismissed with "Save anyway".
  final Set<String> _keepDuplicates = {};

  /// Drafts whose recurring offer was answered.
  final Set<String> _recurringAnswered = {};

  /// The field picker open on a slip: (draft index, field).
  (int, String)? _picking;

  late XpenseScope _scope;

  @override
  XpenseActions get saveActions => _scope.actions;

  @override
  String get saveSurfaceId => _scope.surfaceId;

  @override
  SurfaceStore? get saveStore => widget.store;

  @override
  String get initialStatus => widget.initialStatus;

  @override
  void initState() {
    super.initState();
    _rememberGuesses();
    restoreSaveState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = XpenseScope.of(context);
  }

  @override
  void didUpdateWidget(EntryListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rememberGuesses();
  }

  void _rememberGuesses() {
    for (final raw in widget.drafts) {
      if (raw is! Map) continue;
      final id = raw['id'];
      if (id is! String || _guesses.containsKey(id)) continue;
      _guesses[id] = {
        for (final field in raw['guessed'] as List? ?? const [])
          if (field is String) field: raw[field],
      };
    }
  }

  bool get _editable => widget.onDraftsChanged != null && !isSaved && !saving;

  /// Opens the new-account sheet; the slips read the household again once
  /// it closes, so a new account is offered at once.
  Future<void> _addAccount() async {
    await _scope.actions.openAddAccount();
    if (mounted) setState(() {});
  }

  /// "Fix it in the form": a save there settles this draft on the card.
  Future<void> _openInForm(Object? raw) => openInForm(
    raw,
    current: () => widget.drafts,
    write: widget.onDraftsChanged,
    announce: context.l10n.a2uiSavedEntries(1),
  );

  void _write(int index, String field, Object? value) {
    final next = [
      for (final d in widget.drafts)
        if (d is Map) Map<String, Object?>.from(d) else d,
    ];
    next[index] = withField(
      next[index]! as Map<String, Object?>,
      field,
      value,
      household: _scope.actions.household,
    );
    setState(() => _picking = null);
    widget.onDraftsChanged!(next);
  }

  List<DraftCorrection> _corrections(List<EntryDraft> drafts) => [
    for (final draft in drafts)
      for (final MapEntry(key: field, value: guessed)
          in (_guesses[draft.id] ?? const <String, Object?>{}).entries)
        if (draft.toJson()[field] != guessed)
          DraftCorrection(
            draftId: draft.id,
            field: field,
            guessed: guessed,
            chosen: draft.toJson()[field],
            title: draft.title,
          ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final household = _scope.actions.household;
    final check = checkDrafts(widget.drafts, household.refs);
    final count = check.drafts.length;
    final unansweredDuplicate = check.drafts.any(
      (d) =>
          d.draft?.duplicate != null && !_keepDuplicates.contains(d.draft!.id),
    );
    final canSave =
        check.canSave && !unansweredDuplicate && !saving && !isSaved;
    final onlyIntentLeft = check.drafts.any(
      (d) => d.missing.length == 1 && d.missing.single == 'intent',
    );
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null) ...[
          Text(widget.title!, style: type.subhead),
          const SizedBox(height: XpSpace.s12),
        ],
        if (check.tooMany)
          _Problem(l10n.a2uiTooManyDrafts(maxDraftsPerSurface)),
        for (final (i, draftCheck) in check.drafts.indexed) ...[
          if (i > 0) const SizedBox(height: XpSpace.s12),
          if (draftCheck.isMalformed)
            NeedsReviewSlip(
              raw: draftCheck.raw,
              onEdit: () => unawaited(_openInForm(draftCheck.raw)),
            )
          else if (isSaved)
            SavedSlip(
              draft: draftCheck.draft!,
              categoryName: household
                  .category(draftCheck.draft!.categoryId)
                  ?.name,
              budget: saved?.budgets[draftCheck.draft!.id],
            )
          else
            EntrySlipView(
              check: draftCheck,
              household: household,
              picking: _picking?.$1 == i ? _picking!.$2 : null,
              onPick: _editable
                  ? (field) => setState(
                      () =>
                          _picking = _picking == (i, field) ? null : (i, field),
                    )
                  : null,
              onAnswer: _editable
                  ? (field, value) => _write(i, field, value)
                  : null,
              duplicateKept: _keepDuplicates.contains(draftCheck.draft!.id),
              onKeepDuplicate: () =>
                  setState(() => _keepDuplicates.add(draftCheck.draft!.id)),
              onViewDuplicate: _scope.actions.openTransaction,
              onRate: _scope.actions.setDailyRate,
              onRateSaved: () => setState(() {}),
              onEdit: () => unawaited(_openInForm(draftCheck.raw)),
              onAddAccount: () => unawaited(_addAccount()),
            ),
        ],
        const SizedBox(height: XpSpace.s16),
        if (isSaved)
          _savedFooter(context, check)
        else ...[
          XpButton.primary(
            label: saving
                ? l10n.a2uiSaving
                : count == 2
                ? l10n.a2uiSaveBoth
                : l10n.a2uiSaveEntries(count),
            onPressed: canSave
                ? () => unawaited(
                    saveDrafts(
                      [for (final d in check.drafts) d.draft!],
                      announce: l10n.a2uiSavedEntries(count),
                      corrections: _corrections([
                        for (final d in check.drafts) d.draft!,
                      ]),
                    ),
                  )
                : null,
          ),
          if (failure != null)
            _Problem(
              failure == SaveFailure.rateNeeded
                  ? l10n.a2uiSaveRateNeeded
                  : l10n.a2uiSaveFailed,
            )
          else if (!canSave && !saving && onlyIntentLeft)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: XpSpace.s6),
              child: Text(
                l10n.a2uiAnswerAbove,
                style: type.meta.copyWith(color: colors.inkSecondary),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ],
    );
  }

  Widget _savedFooter(BuildContext context, DraftsCheck check) {
    final l10n = context.l10n;
    final offers = [
      for (final d in check.drafts)
        if (d.draft case final EntryDraft draft
            // The hint is only there at or above the configured
            // `recurring_offer` (the agent and the phone's draft builder
            // both filter it), so the card trusts it.
            when saved != null &&
                draft.recurring != null &&
                !_recurringAnswered.contains(draft.id))
          draft,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.a2uiSavedEntries(check.drafts.length),
                  style: XpType.of(context).subhead,
                ),
              ),
            ),
            if (canUndo)
              XpButton.text(
                label: l10n.a2uiUndo,
                onPressed: undoing ? null : () => unawaited(undoSave()),
              ),
          ],
        ),
        if (undoFailed) _Problem(l10n.a2uiUndoFailed),
        for (final draft in offers)
          RecurringOffer(
            draft: draft,
            onAccept: (mode) {
              setState(() => _recurringAnswered.add(draft.id));
              unawaited(_scope.actions.setRecurring(draft.id, mode));
            },
            onDecline: () => setState(() => _recurringAnswered.add(draft.id)),
          ),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.symmetric(vertical: XpSpace.s6),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: XpType.of(context).meta
            .copyWith(color: XpColors.of(context).danger),
        textAlign: TextAlign.center,
      ),
    ),
  );
}
