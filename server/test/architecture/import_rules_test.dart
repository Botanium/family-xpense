import 'dart:io';

import 'package:test/test.dart';

/// Packages or libraries that only one server module may import
/// (ARCHITECTURE 4.3, DELEGATION rule 7). Keys are URI prefixes; values are
/// the directories under `lib/` allowed to import them.
const adapterOnly = <String, Set<String>>{
  // Experimental Agents API: only the runtime module.
  'package:genkit/experimental': {'runtime'},
  // FirestoreSessionStore, pre-1.0 (D-31).
  'package:genkit_google_cloud/': {'runtime'},
  // Admin gateway: Firestore, Auth, App Check, Messaging (D-06).
  'package:firebase_admin_sdk/': {'admin'},
  'package:google_cloud_firestore/': {'admin', 'runtime'},
  // Telemetry setup (D-29).
  'package:genkit_otel/': {'telemetry'},
  'package:dartastic_opentelemetry/': {'telemetry'},
};

final _directive = RegExp(r'^\s*(?:import|export)\s+([^;]+);', multiLine: true);
final _quoted = RegExp('''['"]([^'"]+)['"]''');

/// Returns the violations in one file, given its path relative to `lib/`.
List<String> check(String libPath, String source) {
  final module = libPath.contains('/') ? libPath.split('/').first : '';
  return [
    for (final directive in _directive.allMatches(source))
      for (final quoted in _quoted.allMatches(directive.group(1)!))
        for (final MapEntry(key: prefix, value: allowed) in adapterOnly.entries)
          if (quoted.group(1)!.startsWith(prefix) && !allowed.contains(module))
            _message(libPath, quoted.group(1)!, allowed),
  ];
}

String _message(String libPath, String uri, Set<String> allowed) {
  final modules = allowed.map((m) => 'lib/$m/').join(', ');
  return 'lib/$libPath imports $uri; only $modules may';
}

void main() {
  test('server/lib keeps pre-1.0 packages in their module', () {
    final violations = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final libPath = file.path.substring('lib/'.length);
      violations.addAll(check(libPath, file.readAsStringSync()));
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('checker flags experimental genkit outside runtime/', () {
    const source = "import 'package:genkit/experimental.dart';";
    expect(check('runtime/agent.dart', source), isEmpty);
    expect(check('tools/ledger.dart', source), hasLength(1));
    expect(check('genkit.dart', source), hasLength(1));
    expect(
      check('tools/ledger.dart', "import 'package:genkit/genkit.dart';"),
      isEmpty,
    );
  });

  test('checker flags admin SDK and telemetry outside their modules', () {
    expect(
      check('auth/p.dart', "import 'package:firebase_admin_sdk/x.dart';"),
      hasLength(1),
    );
    expect(
      check('admin/g.dart', "import 'package:firebase_admin_sdk/x.dart';"),
      isEmpty,
    );
    expect(
      check('genkit.dart', "import 'package:genkit_otel/genkit_otel.dart';"),
      hasLength(1),
    );
  });
}
