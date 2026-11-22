// The phone half of the catalog parity test (A2UI_CATALOG 1, story S3.2):
// xpense_catalog.json, read with a2ui_core 0.8's Catalog.fromJson, against
// the Dart implementations. The server half (loadCatalog, Express compile)
// is packages/xpense_shared/test/catalog/catalog_server_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:a2ui_core/a2ui_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/a2ui/catalog/xpense_catalog.dart';
import 'package:xpense_shared/xpense_shared.dart';

Map<String, Object?> _json() => jsonDecode(
  File('../packages/xpense_shared/$xpenseCatalogPackagePath')
      .readAsStringSync(),
) as Map<String, Object?>;

/// [schema] without descriptions and defaults: they are prompt text, not
/// contract, and the Dart schemas leave them to the JSON.
Object? _contract(Object? schema) => switch (schema) {
  final Map<Object?, Object?> m => {
    for (final MapEntry(:key, :value) in m.entries)
      if (key != 'description' && key != 'default') key: _contract(value),
  },
  final List<Object?> l => [for (final v in l) _contract(v)],
  _ => schema,
};

/// The property names of a component schema, in order.
List<String> _props(Map<String, Object?> schema) {
  final allOf = schema['allOf'];
  final body = allOf is List
      ? allOf.whereType<Map<String, Object?>>().firstWhere(
          (p) => p.containsKey('properties'),
        )
      : schema;
  return (body['properties']! as Map).keys.cast<String>().toList();
}

void main() {
  final json = _json();
  final fromJson = Catalog.fromJson(json);
  final phone = xpenseCatalog();

  test('same catalog id and protocol version', () {
    expect(fromJson.id, xpenseCatalogId);
    expect(phone.id, fromJson.id);
    expect(phone.protocolVersion, fromJson.protocolVersion);
  });

  test('same components, in catalog order', () {
    expect(fromJson.components.keys, orderedEquals(xpenseComponentNames));
    expect(phone.components.keys, orderedEquals(xpenseComponentNames));
  });

  for (final name in xpenseComponentNames) {
    test('$name: same properties in the same positional order', () {
      final json = fromJson.components[name]!.schema.value;
      final dart = phone.components[name]!.schema.value;
      expect(_props(dart), orderedEquals(_props(json)));
      expect(_contract(dart), _contract(json), reason: name);
    });
  }

  test('same functions', () {
    expect(fromJson.functions.keys, orderedEquals(xpenseFunctionNames));
    expect(phone.functions.keys, orderedEquals(xpenseFunctionNames));
    for (final name in xpenseFunctionNames) {
      expect(
        _contract(phone.functions[name]!.argumentSchema.value),
        _contract(fromJson.functions[name]!.argumentSchema.value),
        reason: name,
      );
    }
  });

  test('every shared fixture validates against the phone catalog', () {
    final errors = <String>[];
    final processor = MessageProcessor<ComponentApi>(
      catalogs: [fromJson.withFunctions(const [])],
      onError: (e) => errors.add('${e.code} ${e.message}'),
    );
    addTearDown(processor.dispose);
    final dir = Directory('../packages/xpense_shared/test/fixtures/surfaces');
    for (final file in dir.listSync().whereType<File>()) {
      final messages = jsonDecode(file.readAsStringSync());
      expect(
        processor.processMessagesWithErrors(messages),
        isEmpty,
        reason: file.path,
      );
    }
    expect(errors, isEmpty);
  });
}
