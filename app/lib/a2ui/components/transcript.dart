import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/conversation_views.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';

/// `Transcript(text, seconds?)` (A2UI_CATALOG 3.2).
final ComponentImplementation transcriptComponent = ComponentImplementation(
  name: 'Transcript',
  schema: componentSchema('Transcript', [
    Prop.string('text', required: true),
    Prop.number('seconds'),
  ]),
  builder: (context, node, props, buildChild) => TranscriptView(
    text: props.string('text') ?? '',
    seconds: intOf(props.value('seconds')),
  ),
);
