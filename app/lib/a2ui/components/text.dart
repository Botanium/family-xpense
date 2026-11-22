import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/restricted_markdown.dart';

/// `Text(text, variant?)` (A2UI_CATALOG 3.1), with restricted Markdown.
final ComponentImplementation textComponent = ComponentImplementation(
  name: 'Text',
  schema: componentSchema('Text', [
    Prop.string('text', required: true),
    Prop.oneOf('variant', const ['caption', 'body']),
  ]),
  builder: (context, node, props, buildChild) => RestrictedMarkdown(
    props.string('text') ?? '',
    variant: props.string('variant') == 'caption'
        ? TextVariant.caption
        : TextVariant.body,
  ),
);
