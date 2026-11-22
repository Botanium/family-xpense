import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/conversation_views.dart';

/// `SavedNote(text, tone?)` (A2UI_CATALOG 3.2).
final ComponentImplementation savedNoteComponent = ComponentImplementation(
  name: 'SavedNote',
  schema: componentSchema('SavedNote', [
    Prop.string('text', required: true),
    Prop.oneOf('tone', const ['ok', 'info', 'warn']),
  ]),
  builder: (context, node, props, buildChild) => SavedNoteView(
    text: props.string('text') ?? '',
    tone: NoteTone.values.asNameMap()[props.string('tone')] ?? NoteTone.ok,
  ),
);
