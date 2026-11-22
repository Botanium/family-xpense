import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/figure_cards.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';

/// `GoalCard(name, savedMinor, targetMinor, currency, pace?, goalId?)`
/// (A2UI_CATALOG 3.3).
final ComponentImplementation goalCardComponent = ComponentImplementation(
  name: 'GoalCard',
  schema: componentSchema('GoalCard', [
    Prop.string('name', required: true),
    Prop.number('savedMinor', required: true),
    Prop.number('targetMinor', required: true),
    Prop.string('currency', required: true),
    Prop.string('pace'),
    Prop.string('goalId'),
  ]),
  builder: (context, node, props, buildChild) {
    final goalId = props.string('goalId');
    final actions = XpenseScope.of(context).actions;
    return GoalCardView(
      name: props.string('name') ?? '',
      savedMinor: intOf(props.value('savedMinor')) ?? 0,
      targetMinor: intOf(props.value('targetMinor')) ?? 0,
      currency: props.string('currency'),
      pace: props.string('pace'),
      onOpen: goalId == null ? null : () => actions.openGoal(goalId),
    );
  },
);
