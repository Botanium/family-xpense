// The shared surface fixtures (A2UI_CATALOG 8, story S3.5):
// `test/fixtures/surfaces/local_*.json` are the local builder's output for
// fixture_inputs.dart, and `agent_*.json` are agent_blocks.dart compiled by
// genkit_a2ui in strict mode. The app renders both in its golden tests.
//
// Regenerate after a deliberate change with:
//   UPDATE_FIXTURES=1 dart test test/surface/fixtures_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'agent_blocks.dart';
import 'fixture_inputs.dart';

const String _dir = 'test/fixtures/surfaces';
final bool _update = Platform.environment['UPDATE_FIXTURES'] == '1';

const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

/// Compares [messages] with the fixture [name], or writes it when updating.
void _matchFixture(String name, List<Map<String, Object?>> messages) {
  final file = File('$_dir/$name.json');
  final json = jsonDecode(jsonEncode(messages));
  if (_update) {
    file
      ..createSync(recursive: true)
      ..writeAsStringSync('${_pretty.convert(json)}\n');
    return;
  }
  expect(
    file.existsSync(),
    isTrue,
    reason: '$name.json is missing; run with UPDATE_FIXTURES=1',
  );
  expect(json, jsonDecode(file.readAsStringSync()), reason: name);
}

List<Map<String, Object?>> _readFixture(File file) =>
    (jsonDecode(file.readAsStringSync()) as List<Object?>)
        .cast<Map<String, Object?>>();

Map<String, Object?> _createOf(List<Map<String, Object?>> messages) => messages
    .map((m) => m['createSurface'])
    .whereType<Map<String, Object?>>()
    .single;

/// Every value of [node], recursively.
Iterable<Object?> _walk(Object? node) sync* {
  yield node;
  if (node is Map) {
    for (final value in node.values) {
      yield* _walk(value);
    }
  } else if (node is List) {
    for (final item in node) {
      yield* _walk(item);
    }
  }
}

void main() {
  group('local fixtures match the builder', () {
    for (final MapEntry(key: name, value: build) in localFixtures.entries) {
      test(name, () => _matchFixture('local_$name', build()));
    }
  });

  group('agent fixtures match the server compiler', () {
    late Genkit ai;
    late A2uiCatalog catalog;

    setUpAll(() async {
      ai = Genkit(isDevEnv: false);
      catalog = await loadCatalog(
        ai,
        id: xpenseCatalogLookupId,
        file: xpenseCatalogPackagePath,
      );
    });
    tearDownAll(() => ai.shutdown());

    for (final MapEntry(key: name, value: source) in agentBlocks.entries) {
      test(name, () {
        final parser = A2uiStreamParser(catalog: catalog);
        final segments = [
          ...parser.push('<a2ui>\n$source\n</a2ui>').segments,
          ...parser.flush().segments,
        ];
        final messages = (jsonDecode(
          jsonEncode([
            for (final s in segments)
              if (s is EnvelopeSegment) ...s.envelopes,
          ]),
        ) as List<Object?>).cast<Map<String, Object?>>();
        _matchFixture('agent_$name', messages);
      });
    }
  });

  group('the fixture set', () {
    final files =
        Directory(_dir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    test('holds exactly the local and agent fixtures', () {
      expect(files.map((f) => f.uri.pathSegments.last).toSet(), {
        for (final name in localFixtures.keys) 'local_$name.json',
        for (final name in agentBlocks.keys) 'agent_$name.json',
      });
    });

    test('covers every component of the catalog', () {
      final used = <String>{
        for (final file in files)
          for (final c in _createOf(_readFixture(file))['components']! as List)
            (c as Map)['component']! as String,
      };
      expect(used, containsAll(xpenseComponentNames));
      expect(xpenseComponentNames, containsAll(used));
    });

    test('every surface uses the Xpense catalog and v1.0', () {
      for (final file in files) {
        for (final message in _readFixture(file)) {
          expect(message['version'], xpenseProtocolVersion);
        }
        expect(_createOf(_readFixture(file))['catalogId'], xpenseCatalogId);
      }
    });

    test('local surfaces follow the WP-S1 rules', () {
      for (final file in files.where(
        (f) => f.uri.pathSegments.last.startsWith('local_'),
      )) {
        final messages = _readFixture(file);
        expect(messages, hasLength(1), reason: 'one createSurface');
        final create = _createOf(messages);
        expect(isLocalSurfaceId(create['surfaceId']! as String), isTrue);
        for (final node in _walk(create['components'])) {
          if (node is! Map) continue;
          // Bindings are `@path`, calls `@call`; the bare forms fail
          // validation in a2ui_core 0.8.
          expect(node.keys, isNot(contains('call')));
          if (node['event'] case {'name': final String name}) {
            expect(isLocalActionName(name), isTrue, reason: name);
          }
        }
      }
    });
  });
}
