import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/figure_cards.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';

/// `TransactionList(items, emptyText?)` (A2UI_CATALOG 3.3). A tap opens the
/// transaction on the phone (`openTransaction`), never an agent turn.
final ComponentImplementation transactionListComponent =
    ComponentImplementation(
      name: 'TransactionList',
      schema: componentSchema('TransactionList', [
        Prop.value('items', required: true),
        Prop.string('emptyText'),
      ]),
      builder: (context, node, props, buildChild) => TransactionListView(
        items: props
            .list('items')
            .map(TransactionItem.tryParse)
            .nonNulls
            .toList(),
        emptyText: props.string('emptyText'),
        onOpen: XpenseScope.of(context).actions.openTransaction,
      ),
    );
