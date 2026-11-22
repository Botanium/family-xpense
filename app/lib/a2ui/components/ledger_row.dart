import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart' as ui;

/// `LedgerRow(label, amountMinor, currency, dot?)` (A2UI_CATALOG 3.3): dot,
/// label, dotted leader, mono value.
final ComponentImplementation ledgerRowComponent = ComponentImplementation(
  name: 'LedgerRow',
  schema: componentSchema('LedgerRow', [
    Prop.string('label', required: true),
    Prop.number('amountMinor', required: true),
    Prop.string('currency', required: true),
    Prop.oneOf('dot', const ['income', 'spent', 'saved', 'loan', 'neutral']),
  ]),
  builder: (context, node, props, buildChild) {
    final colors = XpColors.of(context);
    final currency = props.string('currency');
    return ui.LedgerRow(
      label: props.string('label') ?? '',
      value:
          moneyLabel(intOf(props.value('amountMinor')) ?? 0, currency) ?? '—',
      dotColor: switch (props.string('dot')) {
        'income' => colors.income,
        'spent' => colors.ink,
        'saved' => colors.saved,
        'loan' => colors.loan,
        'neutral' => colors.inkTertiary,
        _ => null,
      },
    );
  },
);
