import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/draft_fields.dart';
import 'package:xpense_app/a2ui/widgets/draft_saving.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/a2ui/widgets/money_views.dart';
import 'package:xpense_app/a2ui/xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The catalog `ReceiptSummary` (A2UI_CATALOG 3.2): merchant and total,
/// the "Read on device" chip, the "Split by category" switch (which
/// regroups the drafts on the phone so the groups always add up to the
/// total), one row per entry, Retake and "Save n entries".
class ReceiptSummaryView extends StatefulWidget {
  /// Creates the summary.
  const new({
    required this.receipt,
    required this.drafts,
    required this.split,
    this.source,
    this.onSplitChanged,
    this.onDraftsChanged,
    this.store,
    super.key,
  });

  /// The receipt, or null when it could not be read.
  final SurfaceReceipt? receipt;

  /// The value at `/drafts`.
  final List<Object?> drafts;

  /// Whether the receipt is split by category.
  final bool split;

  /// `device` or `cloud`.
  final String? source;

  /// Writes the switch; null when unbound.
  final ValueChanged<bool>? onSplitChanged;

  /// Writes the drafts; null when unbound.
  final ValueChanged<List<Object?>>? onDraftsChanged;

  /// The surface's data model, for the saved state.
  final SurfaceStore? store;

  @override
  State<ReceiptSummaryView> createState() => _ReceiptSummaryViewState();
}

class _ReceiptSummaryViewState extends State<ReceiptSummaryView>
    with DraftSaving<ReceiptSummaryView> {
  late XpenseScope _scope;

  @override
  XpenseActions get saveActions => _scope.actions;

  @override
  String get saveSurfaceId => _scope.surfaceId;

  @override
  SurfaceStore? get saveStore => widget.store;

  @override
  String get initialStatus => 'review';

  @override
  void initState() {
    super.initState();
    restoreSaveState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = XpenseScope.of(context);
  }

  /// Opens the new-account sheet, then reads the household again.
  Future<void> _addAccount() async {
    await _scope.actions.openAddAccount();
    if (mounted) setState(() {});
  }

  bool get _editable => widget.onDraftsChanged != null && !isSaved && !saving;

  void _toggleSplit(bool split) {
    final receipt = widget.receipt;
    if (receipt == null) return;
    final maps = [
      for (final d in widget.drafts)
        if (d is Map) Map<String, Object?>.from(d),
    ];
    widget.onSplitChanged?.call(split);
    widget.onDraftsChanged?.call(
      draftsForGroups(maps, groupReceipt(receipt, split: split)),
    );
  }

  void _setAccount(String accountId) {
    widget.onDraftsChanged!([
      for (final d in widget.drafts)
        if (d is Map)
          withField(
            Map<String, Object?>.from(d),
            'accountId',
            accountId,
            household: _scope.actions.household,
          )
        else
          d,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final receipt = widget.receipt;
    final household = _scope.actions.household;
    if (receipt == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.a2uiReceiptUnreadable, style: type.body),
          XpButton.secondary(
            label: l10n.a2uiReceiptRetake,
            onPressed: _scope.actions.retakeReceipt,
          ),
        ],
      );
    }
    final check = checkDrafts(widget.drafts, household.refs);
    final first = check.drafts.firstOrNull?.draft;
    final account = household.account(first?.accountId)?.name;
    final meta = [
      dayLabel(context, receipt.occurredOn, time: receipt.occurredTime),
      ?account,
    ].join(' · ');
    final needsAccount = check.drafts.any(
      (d) => d.missing.contains('accountId'),
    );
    final otherProblem = check.drafts.any(
      (d) => d.isMalformed || d.issues.any((i) => i.field != 'accountId'),
    );
    final count = check.drafts.length;
    final base = household.baseCurrency;
    final converted = convertedTotal(widget.drafts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          runSpacing: XpSpace.s4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(receipt.merchant, style: type.title),
                Text(
                  meta.toUpperCase(),
                  style: type.monoLabel.copyWith(color: colors.inkSecondary),
                ),
              ],
            ),
            CatalogMoneyText(
              amountMinor: receipt.totalMinor,
              currency: receipt.currency,
              size: FigureSize.large,
              textAlign: TextAlign.end,
              // The whole receipt's converted amount: every entry's, summed.
              approx: converted != null && receipt.currency != base
                  ? approxLabel(context, converted, base)
                  : null,
            ),
          ],
        ),
        if (widget.source == 'device') ...[
          const SizedBox(height: XpSpace.s8),
          Row(
            children: [
              XpIcon(
                XpGlyph.lock,
                size: XpSpace.iconPill,
                color: colors.inkSecondary,
              ),
              const SizedBox(width: XpSpace.s4),
              Text(
                l10n.a2uiReceiptOnDevice,
                style: type.meta.copyWith(color: colors.inkSecondary),
              ),
            ],
          ),
        ],
        const SizedBox(height: XpSpace.s8),
        Row(
          children: [
            Expanded(child: Text(l10n.a2uiReceiptSplit, style: type.subhead)),
            XpSwitch(
              value: widget.split,
              onChanged: _editable && widget.onSplitChanged != null
                  ? _toggleSplit
                  : null,
              semanticLabel: l10n.a2uiReceiptSplit,
            ),
          ],
        ),
        for (final d in check.drafts)
          if (d.draft case final EntryDraft draft) ...[
            const Hairline(),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: XpSpace.receiptGroupRow,
              ),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text:
                              household.category(draft.categoryId)?.name ??
                              l10n.a2uiReceiptUncategorized,
                          style: type.subhead,
                          children: [
                            const TextSpan(text: '  '),
                            TextSpan(
                              text: l10n.a2uiReceiptItems(
                                receipt.lines
                                    .where(
                                      (l) =>
                                          !widget.split ||
                                          l.categoryId == draft.categoryId,
                                    )
                                    .length,
                              ),
                              style: type.meta.copyWith(
                                color: colors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: XpSpace.s8),
                    CatalogMoneyText(
                      amountMinor: draft.amountMinor ?? 0,
                      currency: draft.currency,
                    ),
                  ],
                ),
              ),
            ),
          ],
        const Hairline(),
        if (needsAccount && _editable && household.accounts.isEmpty) ...[
          // Nothing to pay from: say so and offer to add an account.
          const SizedBox(height: XpSpace.s12),
          Text(l10n.a2uiNoAccounts, style: type.subhead),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: XpButton.text(
              key: const ValueKey('add_account'),
              label: l10n.a2uiAddAccount,
              onPressed: () => unawaited(_addAccount()),
            ),
          ),
        ] else if (needsAccount && _editable) ...[
          const SizedBox(height: XpSpace.s12),
          Text(l10n.a2uiAskAccount, style: type.subhead),
          const SizedBox(height: XpSpace.s8),
          Wrap(
            spacing: XpSpace.s8,
            runSpacing: XpSpace.s8,
            children: [
              for (final option in fieldOptions(
                context,
                household,
                first ?? EntryDraft(id: 'r', intent: 'expense'),
                'accountId',
              ))
                XpChip(
                  key: ValueKey('pick_accountId_${option.value}'),
                  label: option.label,
                  onPressed: () => _setAccount(option.value as String),
                ),
            ],
          ),
        ],
        if (otherProblem && !isSaved)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: XpButton.text(
              label: l10n.a2uiFixInForm,
              onPressed: () => _scope.actions.openManualForm(
                widget.drafts.firstOrNull is Map
                    ? Map<String, Object?>.from(widget.drafts.first! as Map)
                    : const {},
              ),
            ),
          ),
        const SizedBox(height: XpSpace.s16),
        if (isSaved) ...[
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    l10n.a2uiSavedEntries(count),
                    style: type.subhead,
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
          if (undoFailed)
            Semantics(
              liveRegion: true,
              child: Text(
                l10n.a2uiUndoFailed,
                style: type.meta.copyWith(color: colors.danger),
              ),
            ),
        ] else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final retake = XpButton.secondary(
                label: l10n.a2uiReceiptRetake,
                onPressed: _scope.actions.retakeReceipt,
              );
              final save = XpButton.primary(
                label: saving ? l10n.a2uiSaving : l10n.a2uiSaveEntries(count),
                onPressed: check.canSave && !saving
                    ? () => unawaited(
                        saveDrafts([
                          for (final d in check.drafts) d.draft!,
                        ], announce: l10n.a2uiSavedEntries(count)),
                      )
                    : null,
              );
              // Large text or a narrow sheet: stack, primary first.
              if (rowsStack(context) ||
                  XpSpace.isNarrow(context, constraints.maxWidth)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    save,
                    const SizedBox(height: XpSpace.s8),
                    retake,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: retake),
                  const SizedBox(width: XpSpace.s12),
                  Expanded(flex: 2, child: save),
                ],
              );
            },
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: XpSpace.s6),
              child: Text(
                failure == SaveFailure.rateNeeded
                    ? l10n.a2uiSaveRateNeeded
                    : l10n.a2uiSaveFailed,
                style: type.meta.copyWith(color: colors.danger),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ],
    );
  }
}
