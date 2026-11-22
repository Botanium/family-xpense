import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// Packages `xpense_shared` may depend on (ARCHITECTURE 2).
const allowedDependencies = {
  'clock',
  'collection',
  'decimal',
  'meta',
  'schemantic',
};

/// Import prefixes that would tie the shared core to one side or a platform.
const forbiddenImports = [
  'dart:io',
  'dart:ui',
  'dart:html',
  'dart:js_interop',
  'dart:ffi',
  'package:flutter/',
  'package:flutter_test/',
  'package:firebase',
  'package:cloud_firestore/',
  'package:a2ui_core/',
  'package:a2ui_flutter/',
  'package:genkit',
];

final _directive = RegExp(r'^\s*(?:import|export)\s+([^;]+);', multiLine: true);
final _quoted = RegExp('''['"]([^'"]+)['"]''');

void main() {
  test('depends only on the allowed packages (ARCHITECTURE 2, D-05)', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    final dependencies = (pubspec['dependencies'] as Map? ?? {}).keys.toSet();
    expect(dependencies.difference(allowedDependencies), isEmpty);
  });

  test('lib/ imports no Flutter, dart:io, Firebase, Genkit or a2ui_core', () {
    final violations = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final directive in _directive.allMatches(source)) {
        for (final quoted in _quoted.allMatches(directive.group(1)!)) {
          final uri = quoted.group(1)!;
          if (forbiddenImports.any(uri.startsWith)) {
            violations.add('${file.path}: $uri');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
