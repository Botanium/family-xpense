import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/input_views.dart';

/// `TextField(label, value, placeholder?, variant?)` with `checks`
/// (A2UI_CATALOG 3.1). Typing writes the bound path; the value reaches the
/// agent only if an action echoes the path.
final ComponentImplementation textFieldComponent = ComponentImplementation(
  name: 'TextField',
  schema: componentSchema('TextField', [
    Prop.string('label', required: true),
    Prop.string('value', required: true),
    Prop.string('placeholder'),
    Prop.oneOf('variant', const ['longText', 'number', 'shortText']),
  ], checkable: true),
  builder: (context, node, props, buildChild) {
    final binding = props.writable('value');
    return CatalogTextField(
      label: props.string('label') ?? '',
      value: props.string('value') ?? '',
      placeholder: props.string('placeholder'),
      kind: switch (props.string('variant')) {
        'longText' => TextFieldKind.longText,
        'number' => TextFieldKind.number,
        _ => TextFieldKind.shortText,
      },
      error: props.validationErrors.firstOrNull,
      onChanged: binding?.set,
    );
  },
);
