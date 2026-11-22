import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/figure_cards.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';

/// `LoanCard(personName, direction, outstandingMinor, principalMinor,
/// currency, dueOn?, loanId?)` (A2UI_CATALOG 3.3).
final ComponentImplementation loanCardComponent = ComponentImplementation(
  name: 'LoanCard',
  schema: componentSchema('LoanCard', [
    Prop.string('personName', required: true),
    Prop.oneOf('direction', const ['given', 'taken'], required: true),
    Prop.number('outstandingMinor', required: true),
    Prop.number('principalMinor', required: true),
    Prop.string('currency', required: true),
    Prop.string('dueOn'),
    Prop.string('loanId'),
  ]),
  builder: (context, node, props, buildChild) {
    final loanId = props.string('loanId');
    final actions = XpenseScope.of(context).actions;
    return LoanCardView(
      personName: props.string('personName') ?? '',
      direction: props.string('direction') == 'taken'
          ? LoanDirection.taken
          : LoanDirection.given,
      outstandingMinor: intOf(props.value('outstandingMinor')) ?? 0,
      principalMinor: intOf(props.value('principalMinor')) ?? 0,
      currency: props.string('currency'),
      dueOn: props.string('dueOn'),
      onOpen: loanId == null ? null : () => actions.openLoan(loanId),
    );
  },
);
