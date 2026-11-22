import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/a2ui/widgets/money_views.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// One row of a [BreakdownView].
final class BreakdownItem {
  /// Creates a row.
  const new({
    required this.label,
    required this.amountMinor,
    required this.share,
    this.colorKey,
  });

  /// Reads a row from the data model, or returns null for a bad shape.
  static BreakdownItem? tryParse(Object? json) {
    if (json is! Map) return null;
    final label = json['label'];
    final amount = intOf(json['amountMinor']);
    final share = json['share'];
    final key = json['colorKey'];
    if (label is! String || amount == null) return null;
    return BreakdownItem(
      label: label,
      amountMinor: amount,
      share: share is num ? share : 0,
      colorKey: key is String ? key : null,
    );
  }

  /// Category, account or person.
  final String label;

  /// Total in minor units.
  final int amountMinor;

  /// Share of the whole, 0 to 1.
  final num share;

  /// Colour key such as `cat3`.
  final String? colorKey;
}

/// The catalog `BreakdownList`: totals by category, account or person,
/// each with its dot and share; a total row when labelled.
class BreakdownView extends StatelessWidget {
  /// Creates a breakdown.
  const new({
    required this.items,
    required this.currency,
    this.totalLabel,
    super.key,
  });

  /// The rows.
  final List<BreakdownItem> items;

  /// Their currency.
  final String? currency;

  /// Label of the total row; null hides it.
  final String? totalLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final total = items.fold(0, (sum, i) => sum + i.amountMinor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, item) in items.indexed)
          XpListRow(
            title: item.label,
            subtitle: percentLabel(context, item.share),
            leading: Dot(
              color: item.colorKey == null
                  ? colors.categories[i % colors.categories.length]
                  : colors.category(item.colorKey!),
            ),
            trailing: CatalogMoneyText(
              amountMinor: item.amountMinor,
              currency: currency,
            ),
            showDivider: i < items.length - 1 || totalLabel != null,
          ),
        if (totalLabel != null)
          MergeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: XpSpace.listRow),
              child: Row(
                children: [
                  Expanded(child: Text(totalLabel!, style: type.bodyStrong)),
                  CatalogMoneyText(amountMinor: total, currency: currency),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One row of a [TransactionListView].
final class TransactionItem {
  /// Creates a row.
  const new({
    required this.txnId,
    required this.title,
    required this.amountMinor,
    required this.currency,
    this.subtitle,
    this.type,
    this.occurredOn,
  });

  /// Reads a row from the data model, or returns null for a bad shape.
  static TransactionItem? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['txnId'];
    final title = json['title'];
    final amount = intOf(json['amountMinor']);
    final currency = json['currency'];
    if (id is! String || title is! String || amount == null) return null;
    String? text(String key) =>
        json[key] is String ? json[key] as String : null;
    return TransactionItem(
      txnId: id,
      title: title,
      amountMinor: amount,
      currency: currency is String ? currency : null,
      subtitle: text('subtitle'),
      type: text('type'),
      occurredOn: text('occurredOn'),
    );
  }

  /// The transaction.
  final String txnId;

  /// Merchant or label.
  final String title;

  /// Amount in minor units.
  final int amountMinor;

  /// Currency code.
  final String? currency;

  /// Meta line, such as "Dining · Cash".
  final String? subtitle;

  /// Ledger type, such as `income`.
  final String? type;

  /// Household-local day.
  final String? occurredOn;
}

/// The catalog `TransactionList`: at most 20 saved entries; a tap opens one
/// on the phone.
class TransactionListView extends StatelessWidget {
  /// Creates a list.
  const new({
    required this.items,
    required this.onOpen,
    this.emptyText,
    super.key,
  });

  /// Most rows shown (A2UI_CATALOG 3.3).
  static const int maxRows = 20;

  /// The rows.
  final List<TransactionItem> items;

  /// Opens a transaction.
  final ValueChanged<String>? onOpen;

  /// Shown when there are no rows.
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(message: emptyText ?? context.l10n.a2uiListEmpty);
    }
    final shown = items.take(maxRows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, item) in shown.indexed)
          XpListRow(
            title: item.title,
            subtitle: [
              ?item.subtitle,
              if (item.occurredOn != null) dayLabel(context, item.occurredOn),
            ].join(' · '),
            trailing: CatalogMoneyText(
              amountMinor: item.amountMinor,
              currency: item.currency,
              tone: item.type == 'income' ? FigureTone.income : FigureTone.ink,
            ),
            onTap: onOpen == null ? null : () => onOpen!(item.txnId),
            showDivider: i < shown.length - 1,
          ),
      ],
    );
  }
}

/// The catalog `BudgetMeter`: spent against the limit on a thin bar, in
/// `danger` with words when over.
class BudgetMeterView extends StatelessWidget {
  /// Creates a meter.
  const new({
    required this.label,
    required this.spentMinor,
    required this.limitMinor,
    required this.currency,
    super.key,
  });

  /// The budget name.
  final String label;

  /// Spent, in minor units.
  final int spentMinor;

  /// Limit, in minor units.
  final int limitMinor;

  /// Currency code.
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final l10n = context.l10n;
    final over = spentMinor > limitMinor;
    // A ratio for the bar only; the amounts stay integers.
    final ratio = limitMinor <= 0 ? 1.0 : spentMinor / limitMinor;
    final spent = figureLabel(spentMinor, currency) ?? '—';
    final limit = figureLabel(limitMinor, currency) ?? '—';
    final left = moneyLabel((limitMinor - spentMinor).abs(), currency) ?? '—';
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: XpSpace.s8,
            children: [
              Text(label, style: type.bodyStrong),
              Text(
                l10n.a2uiBudgetFigures(spent, limit),
                style: type.figureBody,
              ),
            ],
          ),
          const SizedBox(height: XpSpace.s6),
          ThinBar(
            value: ratio,
            height: XpSpace.goalBar,
            color: over ? colors.danger : colors.ink,
            semanticLabel: label,
          ),
          const SizedBox(height: XpSpace.s6),
          Text(
            over ? l10n.a2uiBudgetOver(left) : l10n.a2uiBudgetLeft(left),
            style: type.meta.copyWith(
              color: over ? colors.danger : colors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Which way a loan goes, the catalog's `direction`.
enum LoanDirection {
  /// We lent; they owe us.
  given,

  /// We borrowed; we owe them.
  taken,
}

/// The catalog `LoanCard`: who owes whom, the outstanding amount, what has
/// been repaid, and the due date. With a loan id it opens the loan and
/// offers "Record a repayment".
class LoanCardView extends StatelessWidget {
  /// Creates a card.
  const new({
    required this.personName,
    required this.direction,
    required this.outstandingMinor,
    required this.principalMinor,
    required this.currency,
    this.dueOn,
    this.onOpen,
    super.key,
  });

  /// The other person.
  final String personName;

  /// Direction.
  final LoanDirection direction;

  /// Still owed.
  final int outstandingMinor;

  /// Lent or borrowed.
  final int principalMinor;

  /// Currency code.
  final String? currency;

  /// Due day, `YYYY-MM-DD`.
  final String? dueOn;

  /// Opens the loan; null without a loan id.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final l10n = context.l10n;
    final repaid = principalMinor <= 0
        ? 0.0
        : (principalMinor - outstandingMinor) / principalMinor;
    final principal = moneyLabel(principalMinor, currency) ?? '—';
    final meta = [
      l10n.a2uiLoanOf(principal),
      if (dueOn != null) l10n.a2uiLoanDue(dayLabel(context, dueOn)),
    ].join(' · ');
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          direction == LoanDirection.given
              ? l10n.a2uiLoanOwesYou(personName)
              : l10n.a2uiLoanYouOwe(personName),
          style: type.bodyStrong,
        ),
        CatalogMoneyText(
          amountMinor: outstandingMinor,
          currency: currency,
          size: FigureSize.large,
          tone: FigureTone.loan,
        ),
        Text(meta, style: type.meta.copyWith(color: colors.inkSecondary)),
        const SizedBox(height: XpSpace.s6),
        ThinBar(
          value: repaid,
          height: XpSpace.goalBar,
          color: colors.loan,
          semanticLabel: l10n.a2uiLoanRepaid,
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onOpen == null)
          MergeSemantics(child: body)
        else
          XpPressable(onPressed: onOpen, child: body),
        if (onOpen != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: XpButton.text(
              label: l10n.a2uiLoanRecordRepayment,
              onPressed: onOpen,
            ),
          ),
      ],
    );
  }
}

/// The catalog `GoalCard`: the Signal goal bar with saved against target.
class GoalCardView extends StatelessWidget {
  /// Creates a card.
  const new({
    required this.name,
    required this.savedMinor,
    required this.targetMinor,
    required this.currency,
    this.pace,
    this.onOpen,
    super.key,
  });

  /// Goal name.
  final String name;

  /// Saved so far.
  final int savedMinor;

  /// Target.
  final int targetMinor;

  /// Currency code.
  final String? currency;

  /// Pace line.
  final String? pace;

  /// Opens the goal; null without a goal id.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final saved = moneyLabel(savedMinor, currency) ?? '—';
    final target = moneyLabel(targetMinor, currency) ?? '—';
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GoalBar(
          label: name,
          value: targetMinor <= 0 ? 0 : savedMinor / targetMinor,
          pace: pace,
        ),
        const SizedBox(height: XpSpace.s4),
        Text(
          context.l10n.a2uiGoalFigures(saved, target),
          style: type.figureSmall.copyWith(color: colors.inkSecondary),
        ),
      ],
    );
    return onOpen == null
        ? MergeSemantics(child: body)
        : XpPressable(onPressed: onOpen, child: body);
  }
}
