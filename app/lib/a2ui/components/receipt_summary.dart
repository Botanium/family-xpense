import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/components/support.dart';
import 'package:xpense_app/a2ui/widgets/draft_saving.dart';
import 'package:xpense_app/a2ui/widgets/receipt_summary_view.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// `ReceiptSummary(receipt, drafts, split, source?)` (A2UI_CATALOG 3.2).
final ComponentImplementation receiptSummaryComponent = ComponentImplementation(
  name: 'ReceiptSummary',
  schema: componentSchema('ReceiptSummary', [
    Prop.value('receipt', required: true),
    Prop.value('drafts', required: true),
    Prop.boolean('split', required: true),
    Prop.oneOf('source', const ['device', 'cloud']),
  ]),
  builder: (context, node, props, buildChild) {
    final model = dataModelOf(node);
    return ReceiptSummaryView(
      receipt: receiptFromJson(props.value('receipt')),
      drafts: props.list('drafts'),
      split: props.boolean('split') ?? false,
      source: props.string('source'),
      onSplitChanged: props.writable('split')?.set,
      onDraftsChanged: props.writable('drafts')?.set,
      store: model == null
          ? null
          : SurfaceStore(read: model.get, write: model.set),
    );
  },
);
