import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/flex_layout.dart';

/// `Column(children, justify?, align?)` (A2UI_CATALOG 3.1).
final ComponentImplementation columnComponent = ComponentImplementation(
  name: 'Column',
  schema: componentSchema('Column', [
    Prop.children('children', required: true),
    Prop.oneOf('justify', const [
      'start',
      'center',
      'end',
      'spaceBetween',
      'spaceAround',
      'spaceEvenly',
      'stretch',
    ]),
    Prop.oneOf('align', const ['center', 'end', 'start', 'stretch']),
  ]),
  builder: (context, node, props, buildChild) => XpFlex(
    direction: Axis.vertical,
    justify: props.string('justify'),
    align: props.string('align'),
    children: [
      for (final child in props.children('children'))
        if (!child.isPlaceholder) buildChild(child),
    ],
  ),
);
