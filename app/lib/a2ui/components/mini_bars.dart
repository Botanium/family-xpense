import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/catalog/schema_dsl.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/a2ui/widgets/money_views.dart';

/// `MiniBars(values, caption?, highlight?, description)`
/// (A2UI_CATALOG 3.3). `description` is the required spoken summary.
final ComponentImplementation miniBarsComponent = ComponentImplementation(
  name: 'MiniBars',
  schema: componentSchema('MiniBars', [
    Prop.value('values', required: true),
    Prop.string('caption'),
    Prop.oneOf('highlight', const ['last', 'max', 'none']),
    Prop.string('description', required: true),
  ]),
  builder: (context, node, props, buildChild) => CatalogMiniBars(
    values: [for (final v in props.list('values')) intOf(v) ?? 0],
    description: props.string('description') ?? '',
    caption: props.string('caption'),
    highlight:
        BarHighlight.values.asNameMap()[props.string('highlight')] ??
        BarHighlight.last,
  ),
);
