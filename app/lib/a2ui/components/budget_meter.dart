import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/figure_cards.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';

/// `BudgetMeter(label, spentMinor, limitMinor, currency)` (A2UI_CATALOG 3.3).
final ComponentImplementation budgetMeterComponent = ComponentImplementation(
  name: 'BudgetMeter',
  schema: componentSchema('BudgetMeter', [
    Prop.string('label', required: true),
    Prop.number('spentMinor', required: true),
    Prop.number('limitMinor', required: true),
    Prop.string('currency', required: true),
  ]),
  builder: (context, node, props, buildChild) => BudgetMeterView(
    label: props.string('label') ?? '',
    spentMinor: intOf(props.value('spentMinor')) ?? 0,
    limitMinor: intOf(props.value('limitMinor')) ?? 0,
    currency: props.string('currency'),
  ),
);
