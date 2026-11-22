import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/a2ui/widgets/money_views.dart';

/// `MoneyText(amountMinor, currency, size?, sign?, tone?, approx?)`
/// (A2UI_CATALOG 3.3). The phone formats the amount; the agent never does.
final ComponentImplementation moneyTextComponent = ComponentImplementation(
  name: 'MoneyText',
  schema: componentSchema('MoneyText', [
    Prop.number('amountMinor', required: true),
    Prop.string('currency', required: true),
    Prop.oneOf('size', const ['hero', 'large', 'body', 'small']),
    Prop.oneOf('sign', const ['none', 'plus', 'minus']),
    Prop.oneOf('tone', const ['ink', 'income', 'muted', 'loan', 'saving']),
    Prop.value('approx'),
  ]),
  builder: (context, node, props, buildChild) {
    final approx = props.value('approx');
    final approxMinor = approx is Map ? intOf(approx['amountMinor']) : null;
    final approxCurrency = approx is Map ? approx['currency'] : null;
    return CatalogMoneyText(
      amountMinor: intOf(props.value('amountMinor')) ?? 0,
      currency: props.string('currency'),
      size:
          FigureSize.values.asNameMap()[props.string('size')] ??
          FigureSize.body,
      sign:
          FigureSign.values.asNameMap()[props.string('sign')] ??
          FigureSign.none,
      tone:
          FigureTone.values.asNameMap()[props.string('tone')] ?? FigureTone.ink,
      approx: approxMinor == null || approxCurrency is! String
          ? null
          : approxLabel(context, approxMinor, approxCurrency),
    );
  },
);
