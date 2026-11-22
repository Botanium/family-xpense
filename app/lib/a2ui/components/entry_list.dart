import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/components/support.dart';
import 'package:xpense_app/a2ui/widgets/draft_saving.dart';
import 'package:xpense_app/a2ui/widgets/entry_list_view.dart';

/// `EntryList(drafts, status?, title?)` (A2UI_CATALOG 3.2): the smart
/// component that edits, validates and saves drafts on the phone. `status`
/// is static; after a save the phone keeps its own state at `/ui/status`.
final ComponentImplementation entryListComponent = ComponentImplementation(
  name: 'EntryList',
  schema: componentSchema('EntryList', [
    Prop.value('drafts', required: true),
    Prop.oneOf('status', const ['review', 'saved']),
    Prop.string('title'),
  ]),
  builder: (context, node, props, buildChild) {
    final binding = props.writable('drafts');
    final model = dataModelOf(node);
    return EntryListView(
      drafts: props.list('drafts'),
      title: props.string('title'),
      initialStatus: props.string('status') ?? 'review',
      onDraftsChanged: binding?.set,
      store: model == null
          ? null
          : SurfaceStore(read: model.get, write: model.set),
    );
  },
);
