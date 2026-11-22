import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/flex_layout.dart';

/// `Row(children, justify?, align?)` (A2UI_CATALOG 3.1).
final ComponentImplementation rowComponent = ComponentImplementation(
  name: 'Row',
  schema: componentSchema('Row', [
    Prop.children('children', required: true),
    Prop.oneOf('justify', const [
      'center',
      'end',
      'spaceAround',
      'spaceBetween',
      'spaceEvenly',
      'start',
      'stretch',
    ]),
    Prop.oneOf('align', const ['start', 'center', 'end', 'stretch']),
  ]),
  builder: (context, node, props, buildChild) => XpFlex(
    direction: Axis.horizontal,
    justify: props.string('justify'),
    align: props.string('align'),
    children: [
      for (final child in props.children('children'))
        if (!child.isPlaceholder) buildChild(child),
    ],
  ),
);
