import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/draft_fields.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/a2ui/widgets/money_views.dart';
import 'package:xpense_app/a2ui/xpense_actions.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Chips shown before "More…" in a field picker.
const int _shownOptions = 5;

/// One draft on an `EntryList` in review: the mono header, the amount with
/// its converted value, the field rows (tap one to change it), problems,
/// the duplicate hint, today's rate, and the question for the first
/// missing field.
class EntrySlipView extends StatefulWidget {
  /// Creates a slip for a draft that passed the shape check.
  const new({
    required this.check,
    required this.household,
    required this.onPick,
    required this.onAnswer,
    required this.onKeepDuplicate,
    required this.onViewDuplicate,
    required this.onRate,
    required this.onRateSaved,
    required this.onEdit,
    this.onAddAccount,
    this.picking,
    this.duplicateKept = false,
    super.key,
  });

  /// The checked draft.
  final DraftCheck check;

  /// The household cache.
  final XpenseHousehold household;

  /// The field whose picker is open.
  final String? picking;

  /// Opens or closes the picker of a field; null when read-only.
  final ValueChanged<String>? onPick;

  /// Writes an answer; null when read-only.
  final void Function(String field, Object value)? onAnswer;

  /// Whether "Save anyway" was tapped on the duplicate hint.
  final bool duplicateKept;

  /// "Save anyway".
  final VoidCallback onKeepDuplicate;

  /// "View" on the duplicate hint.
  final ValueChanged<String> onViewDuplicate;

  /// Saves today's rate.
  final Future<void> Function(String rate) onRate;

  /// Called once today's rate is saved.
  final VoidCallback onRateSaved;

  /// Opens the manual form, for fields only it can set.
  final VoidCallback onEdit;

  /// Opens the new-account sheet, offered when the household has no
  /// account to pay from.
  final VoidCallback? onAddAccount;

  @override
  State<EntrySlipView> createState() => _EntrySlipViewState();
}

class _EntrySlipViewState extends State<EntrySlipView> {
  bool _allOptions = false;

  EntryDraft get _draft => widget.check.draft!;

  @override
  void didUpdateWidget(EntrySlipView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.picking != widget.picking) _allOptions = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final draft = _draft;
    final household = widget.household;
    final guessed = draft.guessed ?? const [];
    final missing = widget.check.missing;
    final hasCategory = draft.intent == 'expense' || draft.intent == 'income';
    final category = hasCategory
        ? fieldValue(context, household, draft, 'categoryId')
        : null;
    final header = [
      intentLabel(context, draft.intent),
      if (hasCategory) category ?? '?',
    ].join(' · ');
    final confidence = lowestConfidence(draft);
    final asked =
        widget.picking ?? missing.where((f) => f != 'intent').firstOrNull;
    final label = type.monoLabel.copyWith(
      color: colors.inkSecondary,
      letterSpacing: 1,
    );
    final headerRow = Row(
      children: [
        Expanded(child: Text(header.toUpperCase(), style: label)),
        if (hasCategory && guessed.contains('categoryId')) ...[
          GuessedBadge(label: l10n.a2uiGuessed),
          const SizedBox(width: XpSpace.s8),
        ],
        if (confidence != null)
          Text(percentLabel(context, confidence), style: label),
      ],
    );
    final headerField = missing.contains('intent') ? 'intent' : 'categoryId';
    return Slip(
      children: [
        if (widget.onPick != null &&
            (hasCategory || missing.contains('intent')))
          XpPressable(
            onPressed: () => widget.onPick!(headerField),
            semanticLabel: l10n.a2uiChangeField(header),
            child: headerRow,
          )
        else
          headerRow,
        _amount(context),
        const DashedRule(),
        for (final (field, name) in slipFields(context, draft))
          _FieldRow(
            label: name,
            value: fieldValue(context, household, draft, field),
            guessed: guessed.contains(field),
            missing: missing.contains(field),
            guessedLabel: l10n.a2uiGuessed,
            onTap: widget.onPick == null ? null : () => widget.onPick!(field),
          ),
        for (final issue in widget.check.issues)
          if (issue is! MissingField)
            Text(
              _issueText(context, issue),
              style: type.meta.copyWith(color: colors.danger),
            ),
        if (_accountCurrency case final accountCurrency?
            when draft.currency != null && accountCurrency != draft.currency)
          Text(
            l10n.a2uiConvertedNote(accountCurrency),
            style: type.meta.copyWith(color: colors.inkSecondary),
          ),
        if (draft.duplicate case final hint? when !widget.duplicateKept)
          _DuplicateHint(
            onView: () => widget.onViewDuplicate(hint.txnId),
            onKeep: widget.onKeepDuplicate,
          ),
        if (_needsRate) _rate(context),
        if (asked != null && widget.onAnswer != null) ...[
          const DashedRule(),
          _question(context, asked),
        ],
      ],
    );
  }

  Widget _amount(BuildContext context) {
    final draft = _draft;
    final base = widget.household.baseCurrency;
    // A quote the draft carries, else a preview at the latest rate, shown
    // only: the save prices the entry with the rate for its date.
    final fx = draft.fx?.baseAmountMinor ?? _previewBaseAmount(draft, base);
    return CatalogMoneyText(
      amountMinor: draft.amountMinor ?? 0,
      currency: draft.currency,
      size: FigureSize.large,
      tone: draft.intent == 'income' ? FigureTone.income : FigureTone.ink,
      approx: fx != null && draft.currency != base
          ? approxLabel(context, fx, base)
          : null,
    );
  }

  int? _previewBaseAmount(EntryDraft draft, String base) {
    final minor = draft.amountMinor;
    final currency = Currency.tryParse(draft.currency ?? '');
    final baseCurrency = Currency.tryParse(base);
    final latest = widget.household.latestRate;
    if (minor == null ||
        currency == null ||
        baseCurrency == null ||
        latest == null ||
        currency == baseCurrency) {
      return null;
    }
    final rate = FxRate.parse(FxPair.usdIqd.code, latest).valueOrNull;
    if (rate == null) return null;
    return toBaseAmount(
      Money(minor, currency),
      baseCurrency,
      rate: rate,
    ).valueOrNull?.minorUnits;
  }

  /// The currency of the draft's account, when it names a known one.
  String? get _accountCurrency =>
      widget.household.account(_draft.accountId)?.currency;

  /// Today's rate is asked when the entry is not in the base currency, or
  /// its account is in the other currency (the save converts it).
  bool get _needsRate {
    final currency = _draft.currency;
    if (widget.onAnswer == null ||
        currency == null ||
        widget.household.rateEnteredToday) {
      return false;
    }
    final account = _accountCurrency;
    return currency != widget.household.baseCurrency ||
        (account != null && account != currency);
  }

  Widget _rate(BuildContext context) {
    final l10n = context.l10n;
    final latest = widget.household.latestRate;
    Future<void> save(String rate) async {
      await widget.onRate(rate);
      if (mounted) widget.onRateSaved();
    }

    // The keypad; a rate more than 5% from the latest is confirmed first
    // (WP-24, a typo guard).
    Future<void> enter(String initial) async {
      final previous = latest == null
          ? null
          : FxRate.forPair(FxPair.usdIqd, latest).valueOrNull;
      final typed = await showRateEntry(
        context: context,
        labels: rateEntryLabelsOf(context, previous: latest),
        initial: initial,
        needsConfirm: previous == null
            ? null
            : (typed) => switch (FxRate.forPair(FxPair.usdIqd, typed)) {
                Ok(:final value) => isRateJump(previous, value),
                Err() => false,
              },
      );
      if (typed != null) await save(typed);
    }

    // The household's first rate: nothing to reuse, so the keypad opens
    // empty.
    if (latest == null) {
      return Row(
        children: [
          Expanded(
            child: Text(l10n.a2uiRateQuestion, style: XpType.of(context).body),
          ),
          XpButton.text(
            label: l10n.a2uiRateEnter,
            onPressed: () => unawaited(enter('')),
          ),
        ],
      );
    }

    return RatePrompt(
      question: l10n.a2uiRateQuestion,
      rate: latest,
      sameLabel: l10n.a2uiRateUse,
      changeLabel: l10n.a2uiRateChange,
      placement: RatePromptPlacement.inline,
      semanticLabel: l10n.a2uiRateSpoken(latest),
      onSame: () => unawaited(save(latest)),
      onChange: () => unawaited(enter(latest)),
    );
  }

  Widget _question(BuildContext context, String field) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final options = fieldOptions(context, widget.household, _draft, field);
    final shown = _allOptions ? options : options.take(_shownOptions).toList();
    final current = field == 'personName'
        ? _draft.personId
        : _draft.toJson()[field];
    // Nothing to pay from: say so and offer to add an account.
    final noAccounts =
        (field == 'accountId' || field == 'toAccountId') &&
        widget.household.accounts.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (noAccounts)
          Text(l10n.a2uiNoAccounts, style: type.subhead)
        else
          Text(fieldQuestion(context, field), style: type.subhead),
        const SizedBox(height: XpSpace.s8),
        if (noAccounts && widget.onAddAccount != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: XpButton.text(
              key: const ValueKey('add_account'),
              label: l10n.a2uiAddAccount,
              onPressed: widget.onAddAccount,
            ),
          )
        else if (options.isEmpty && field != 'occurredOn')
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: XpButton.text(
              label: l10n.a2uiFixInForm,
              onPressed: widget.onEdit,
            ),
          )
        else
          Wrap(
            spacing: XpSpace.s8,
            runSpacing: XpSpace.s8,
            children: [
              for (final option in shown)
                XpChip(
                  key: ValueKey('pick_${field}_${option.value}'),
                  label: option.label,
                  selected: option.value == current,
                  onPressed: () {
                    unawaited(XpHaptics.picked());
                    widget.onAnswer!(field, option.value);
                  },
                ),
              if (!_allOptions && options.length > _shownOptions)
                XpChip(
                  label: l10n.a2uiMore,
                  onPressed: () => setState(() => _allOptions = true),
                ),
              if (field == 'occurredOn')
                XpChip(
                  label: l10n.a2uiOtherDay,
                  onPressed: () => unawaited(_pickDay(context)),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _pickDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dayOf(_draft.occurredOn) ?? today(),
      firstDate: DateTime(2000),
      lastDate: today(),
    );
    if (picked == null || !mounted) return;
    widget.onAnswer!('occurredOn', dayString(picked));
  }

  String _issueText(BuildContext context, DraftIssue issue) {
    final l10n = context.l10n;
    return switch (issue) {
      UnknownReference(:final field) => switch (field) {
        'accountId' || 'toAccountId' => l10n.a2uiUnknownAccount,
        'categoryId' => l10n.a2uiUnknownCategory,
        _ => l10n.a2uiUnknownReference,
      },
      WrongCategoryKind() => l10n.a2uiWrongCategoryKind,
      DraftAmountOutOfRange() => l10n.a2uiAmountOutOfRange,
      MissingField() || MalformedField() => l10n.a2uiNeedsReview,
    };
  }
}

class _FieldRow extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.guessed,
    required this.missing,
    required this.guessedLabel,
    required this.onTap,
  });

  final String label;
  final String? value;
  final bool guessed;
  final bool missing;
  final String guessedLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final shown = value ?? '—';
    final row = Row(
      children: [
        Text(label, style: type.caption.copyWith(color: colors.inkSecondary)),
        const SizedBox(width: XpSpace.s8),
        if (guessed) GuessedBadge(label: guessedLabel),
        const SizedBox(width: XpSpace.s8),
        Expanded(
          child: Text(
            shown.toUpperCase(),
            style: type.figureSmall.copyWith(
              color: missing ? colors.inkSecondary : colors.ink,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
    final spoken = [label, shown, if (guessed) guessedLabel].join(', ');
    if (onTap == null) {
      return Semantics(label: spoken, excludeSemantics: true, child: row);
    }
    return XpPressable(
      onPressed: onTap,
      semanticLabel: context.l10n.a2uiChangeField(spoken),
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: XpSpace.minTarget),
        child: row,
      ),
    );
  }
}

class _DuplicateHint extends StatelessWidget {
  const new({required this.onView, required this.onKeep});

  final VoidCallback onView;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    return Semantics(
      container: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: XpSpace.s12,
        children: [
          Text(
            l10n.a2uiDuplicateHint,
            style: type.caption.copyWith(color: XpColors.of(context).danger),
          ),
          XpButton.text(label: l10n.a2uiDuplicateView, onPressed: onView),
          XpButton.text(label: l10n.a2uiDuplicateKeep, onPressed: onKeep),
        ],
      ),
    );
  }
}

/// A draft the app cannot read: "Needs review" and Edit, which opens the
/// manual form. It cannot be saved from the card (A2UI_CATALOG 9).
class NeedsReviewSlip extends StatelessWidget {
  /// Creates the slip.
  const new({required this.raw, required this.onEdit, super.key});

  /// The draft as found.
  final Object? raw;

  /// Opens the manual form.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final title = raw is Map ? (raw! as Map)['title'] : null;
    return Slip(
      children: [
        Text(
          l10n.a2uiNeedsReview.toUpperCase(),
          style: type.monoLabel.copyWith(
            color: colors.danger,
            letterSpacing: 1,
          ),
        ),
        Text(
          title is String ? title : l10n.a2uiNeedsReviewBody,
          style: type.body,
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: XpButton.text(label: l10n.a2uiEdit, onPressed: onEdit),
        ),
      ],
    );
  }
}

/// A saved draft: "SAVED · DINING", the budget standing when there is one,
/// and the amount.
class SavedSlip extends StatelessWidget {
  /// Creates the slip.
  const new({required this.draft, this.categoryName, this.budget, super.key});

  /// The saved draft.
  final EntryDraft draft;

  /// Its category's name.
  final String? categoryName;

  /// Where it leaves its budget.
  final BudgetStanding? budget;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final scope = draft.intent == 'expense' || draft.intent == 'income'
        ? draft.categoryId
        : null;
    final what = scope == null
        ? intentLabel(context, draft.intent)
        : categoryName ?? scope;
    final standing = budget == null
        ? null
        : l10n.a2uiBudgetFigures(
            figureLabel(budget!.spentMinor, budget!.currency) ?? '—',
            figureLabel(budget!.limitMinor, budget!.currency) ?? '—',
          );
    return Slip(
      children: [
        Row(
          children: [
            XpIcon(XpGlyph.check, size: XpSpace.iconRow, color: colors.income),
            const SizedBox(width: XpSpace.s8),
            Expanded(
              child: Text(
                [
                  l10n.a2uiSavedLabel,
                  what,
                  ?standing,
                ].join(' · ').toUpperCase(),
                style: type.monoLabel.copyWith(
                  color: colors.inkSecondary,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(child: Text(draft.title ?? '', style: type.body)),
            CatalogMoneyText(
              amountMinor: draft.amountMinor ?? 0,
              currency: draft.currency,
              tone: draft.intent == 'income'
                  ? FigureTone.income
                  : FigureTone.ink,
            ),
          ],
        ),
      ],
    );
  }
}

/// "Repeat every month on the 5th?" after a save, when the draft's
/// recurring guess is strong enough.
class RecurringOffer extends StatelessWidget {
  /// Creates the offer.
  const new({
    required this.draft,
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  /// The saved draft with a recurring guess.
  final EntryDraft draft;

  /// Makes it recurring.
  final ValueChanged<RecurringMode> onAccept;

  /// Declines.
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hint = draft.recurring!;
    final weekly = hint.unit == 'week';
    final question = weekly
        ? l10n.a2uiRecurringWeekly(draft.title ?? '')
        : hint.dayOfMonth == null
        ? l10n.a2uiRecurringMonthly(draft.title ?? '')
        : l10n.a2uiRecurringMonthlyOn(draft.title ?? '', hint.dayOfMonth!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Hairline(),
        Padding(
          padding: const EdgeInsetsDirectional.only(top: XpSpace.s8),
          child: Text(question, style: XpType.of(context).caption),
        ),
        Wrap(
          spacing: XpSpace.s12,
          children: [
            XpButton.text(
              label: l10n.a2uiRecurringYes,
              onPressed: () => onAccept(
                weekly ? RecurringMode.weekly : RecurringMode.monthly,
              ),
            ),
            XpButton.text(label: l10n.a2uiRecurringNo, onPressed: onDecline),
          ],
        ),
      ],
    );
  }
}
