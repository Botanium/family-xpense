import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/components/support.dart';
import 'package:xpense_app/a2ui/widgets/button_view.dart';
import 'package:xpense_app/a2ui/xpense_scope.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// `Button(child, variant?, action)` with `checks` (A2UI_CATALOG 3.1). A
/// failed check disables it and shows the check's message.
final ComponentImplementation buttonComponent = ComponentImplementation(
  name: 'Button',
  schema: componentSchema('Button', [
    Prop.child('child', required: true),
    Prop.oneOf('variant', const ['default', 'primary', 'borderless']),
    Prop.action('action', required: true),
  ], checkable: true),
  builder: (context, node, props, buildChild) {
    final child = props.child('child');
    final valid = props.isValid;
    return CatalogButton(
      label: child == null ? const SizedBox.shrink() : buildChild(child),
      kind: switch (props.string('variant')) {
        'primary' => XpButtonKind.primary,
        'borderless' => XpButtonKind.text,
        _ => XpButtonKind.secondary,
      },
      onPressed: valid
          ? actionHandler(XpenseScope.of(context), node, props, 'action')
          : null,
      hint: valid ? null : props.validationErrors.firstOrNull,
    );
  },
);
