/// Reads `xpense_catalog.json` for the catalog tests and flattens each
/// component's properties into an ordered list, so tests can compare the
/// JSON with the contract in A2UI_CATALOG 3.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xpense_shared/xpense_shared.dart';

/// The catalog document, decoded.
Map<String, Object?> readCatalogJson() =>
    jsonDecode(File(xpenseCatalogPackagePath).readAsStringSync())
        as Map<String, Object?>;

/// One property of a component, flattened.
typedef CatalogProp = ({String name, String kind, bool required});

/// The component schemas of [catalog], by name, in document order.
Map<String, Map<String, Object?>> componentsOf(Map<String, Object?> catalog) =>
    (catalog['components']! as Map<String, Object?>).map(
      (name, schema) => MapEntry(name, schema! as Map<String, Object?>),
    );

/// Whether a component schema mixes in `Checkable` (so it takes `checks`).
bool isCheckable(Map<String, Object?> schema) =>
    (schema['allOf'] as List<Object?>? ?? const []).any(
      (part) => part is Map && '${part[r'$ref']}'.endsWith('/Checkable'),
    );

/// The properties of a component schema, in positional order, without the
/// `component` discriminator. A `Checkable` schema keeps its properties in
/// the second `allOf` part.
List<CatalogProp> propsOf(Map<String, Object?> schema) {
  final body = isCheckable(schema)
      ? (schema['allOf']! as List<Object?>)
            .whereType<Map<String, Object?>>()
            .firstWhere((part) => part.containsKey('properties'))
      : schema;
  final properties = body['properties']! as Map<String, Object?>;
  final required = (body['required'] as List<Object?>? ?? const [])
      .cast<String>()
      .toSet();
  return [
    for (final MapEntry(key: name, value: prop) in properties.entries)
      if (name != 'component')
        (
          name: name,
          kind: kindOf(prop! as Map<String, Object?>),
          required: required.contains(name),
        ),
  ];
}

/// A short description of a property's type: the common type it references
/// (`DynamicString`, `Action`, …), `enum(a|b)` for a static enum, or the JSON
/// type of any other static property.
String kindOf(Map<String, Object?> prop) {
  final ref = prop[r'$ref'];
  if (ref is String) return ref.split('/').last;
  if (prop['allOf'] case [{r'$ref': final String r}, ...]) {
    return r.split('/').last;
  }
  final values = prop['enum'];
  if (values is List) return 'enum(${values.join('|')})';
  return '${prop['type']}';
}
