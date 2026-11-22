import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/input_views.dart';

/// `DateTimeInput(value, enableDate?, enableTime?, min?, max?, label?)`
/// with `checks` (A2UI_CATALOG 3.1).
final ComponentImplementation dateTimeInputComponent = ComponentImplementation(
  name: 'DateTimeInput',
  schema: componentSchema('DateTimeInput', [
    Prop.string('value', required: true),
    Prop.flag('enableDate'),
    Prop.flag('enableTime'),
    Prop.dateTime('min'),
    Prop.dateTime('max'),
    Prop.string('label'),
  ], checkable: true),
  builder: (context, node, props, buildChild) {
    final enableTime = props.boolean('enableTime') ?? false;
    return CatalogDateTimeField(
      value: props.string('value') ?? '',
      label: props.string('label'),
      // Neither flag set means a date, the common case for money.
      enableDate: (props.boolean('enableDate') ?? false) || !enableTime,
      enableTime: enableTime,
      min: props.string('min'),
      max: props.string('max'),
      onChanged: props.writable('value')?.set,
    );
  },
);
