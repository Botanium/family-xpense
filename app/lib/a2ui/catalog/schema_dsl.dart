/// A small builder for component schemas in the same JSON Schema form as
/// `xpense_catalog.json`: properties reference the A2UI common types by
/// `$ref`, in positional order. The parity test compares the result with
/// the JSON, so each component file reads like its row in A2UI_CATALOG 3.
library;

import 'package:json_schema_builder/json_schema_builder.dart';

const String _commonTypes = r'common_types.json#/$defs/';

Map<String, Object?> _ref(String type) => {r'$ref': '$_commonTypes$type'};

/// One property of a component.
final class Prop {
  /// Creates a property with a raw [schema].
  const new(this.name, this.schema, {this.required = false});

  /// A literal, a binding or a call giving a string.
  new string(this.name, {this.required = false})
    : schema = _ref('DynamicString');

  /// A literal, a binding or a call giving a number.
  new number(this.name, {this.required = false})
    : schema = _ref('DynamicNumber');

  /// A literal, a binding or a call giving a boolean.
  new boolean(this.name, {this.required = false})
    : schema = _ref('DynamicBoolean');

  /// A literal, a binding or a call giving any JSON value.
  new value(this.name, {this.required = false}) : schema = _ref('DynamicValue');

  /// One child component id.
  new child(this.name, {this.required = false}) : schema = _ref('Child');

  /// Child ids, or a template over a data list.
  new children(this.name, {this.required = false}) : schema = _ref('ChildList');

  /// An action.
  new action(this.name, {this.required = false}) : schema = _ref('Action');

  /// A static enum: in Express it cannot be bound (WP-S1).
  new oneOf(this.name, List<String> values, {this.required = false})
    : schema = {'type': 'string', 'enum': values};

  /// A static boolean.
  new flag(this.name, {this.required = false}) : schema = {'type': 'boolean'};

  /// A dynamic string restricted to ISO 8601 dates and times when literal.
  new dateTime(this.name, {this.required = false})
    : schema = {
        'allOf': [
          _ref('DynamicString'),
          {
            'if': {'type': 'string'},
            'then': {
              'oneOf': [
                {'format': 'date'},
                {'format': 'time'},
                {'format': 'date-time'},
              ],
            },
          },
        ],
      };

  /// A static array of objects with string [fields]; [required] fields of
  /// each item are listed in [itemRequired].
  new items(
    this.name,
    List<String> fields, {
    List<String> itemRequired = const [],
    int? minItems,
    int? maxItems,
    this.required = false,
  }) : schema = {
         'type': 'array',
         'minItems': ?minItems,
         'maxItems': ?maxItems,
         'items': {
           'type': 'object',
           'properties': {
             for (final f in fields) f: {'type': 'string'},
           },
           'required': itemRequired,
           'additionalProperties': false,
         },
       };

  /// The property name.
  final String name;

  /// Its JSON Schema.
  final Map<String, Object?> schema;

  /// Whether it must be given.
  final bool required;
}

/// The schema of component [name] with [props] in positional order.
/// [checkable] mixes in `Checkable`, so the component takes `checks`.
Schema componentSchema(
  String name,
  List<Prop> props, {
  bool checkable = false,
}) {
  final body = <String, Object?>{
    'type': 'object',
    'properties': {
      'component': {'const': name},
      for (final p in props) p.name: p.schema,
    },
    'required': [
      'component',
      for (final p in props)
        if (p.required) p.name,
    ],
  };
  return Schema.fromMap(
    checkable
        ? {
            'type': 'object',
            'allOf': [_ref('Checkable'), body],
          }
        : body,
  );
}
