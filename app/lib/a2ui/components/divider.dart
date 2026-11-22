import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// `Divider(axis?)` (A2UI_CATALOG 3.1): a hairline.
final ComponentImplementation dividerComponent = ComponentImplementation(
  name: 'Divider',
  schema: componentSchema('Divider', [
    Prop.oneOf('axis', const ['horizontal', 'vertical']),
  ]),
  builder: (context, node, props, buildChild) =>
      props.string('axis') == 'vertical'
      ? SizedBox(
          width: XpSpace.hairline(context),
          height: XpSpace.s24,
          child: ColoredBox(color: XpColors.of(context).hairline),
        )
      : const Hairline(),
);
