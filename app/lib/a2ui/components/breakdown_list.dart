import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/figure_cards.dart';

/// `BreakdownList(items, currency, totalLabel?)` (A2UI_CATALOG 3.3).
final ComponentImplementation breakdownListComponent = ComponentImplementation(
  name: 'BreakdownList',
  schema: componentSchema('BreakdownList', [
    Prop.value('items', required: true),
    Prop.string('currency', required: true),
    Prop.string('totalLabel'),
  ]),
  builder: (context, node, props, buildChild) => BreakdownView(
    items: props.list('items').map(BreakdownItem.tryParse).nonNulls.toList(),
    currency: props.string('currency'),
    totalLabel: props.string('totalLabel'),
  ),
);
