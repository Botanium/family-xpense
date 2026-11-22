import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'import_rules.dart';

void main() {
  group('app/lib', () {
    test('follows the import rules of ARCHITECTURE 3.1', () {
      final violations = checkLibrary(Directory('lib'));
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('checker', () {
    List<String> reasons(String path, String source) =>
        checkFile(path, source).map((v) => v.reason).toList();

    test('classifies layers by path', () {
      expect(layerOf('features/ask/ask_screen.dart'), Layer.feature);
      expect(layerOf('a2ui/catalog.dart'), Layer.a2ui);
      expect(layerOf('data/accounts_repository.dart'), Layer.data);
      expect(layerOf('services/ocr_engine.dart'), Layer.services);
      expect(layerOf('core/theme/tokens.dart'), Layer.core);
      expect(layerOf('main.dart'), Layer.root);
      expect(featureOf('features/ask/widgets/x.dart'), 'ask');
    });

    test('reads imports, exports and conditional imports', () {
      const source = '''
import 'package:a/a.dart';
import "b.dart" show B;
export 'c.dart';
import 'd_stub.dart'
    if (dart.library.io) 'd_io.dart';
// import 'commented.dart';
''';
      expect(directiveUris(source), [
        'package:a/a.dart',
        'b.dart',
        'c.dart',
        'd_stub.dart',
        'd_io.dart',
      ]);
    });

    test('resolves relative and package imports', () {
      expect(
        resolveInternal('features/ask/a.dart', '../home/b.dart'),
        'features/home/b.dart',
      );
      expect(
        resolveInternal('core/a.dart', 'package:xpense_app/data/r.dart'),
        'data/r.dart',
      );
      expect(resolveInternal('core/a.dart', 'package:other/x.dart'), isNull);
      expect(resolveInternal('core/a.dart', 'dart:async'), isNull);
    });

    test('allows the layering ARCHITECTURE 3.1 permits', () {
      const source = '''
import 'package:xpense_app/core/theme/tokens.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/services/ocr_engine.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/features/ask/ask_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_shared/xpense_shared.dart';
''';
      expect(reasons('features/ask/ask_screen.dart', source), isEmpty);
      expect(
        reasons('a2ui/catalog.dart', '''
import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/material.dart';
import '../core/theme/tokens.dart';
'''),
        isEmpty,
      );
      expect(
        reasons('data/r.dart', '''
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
'''),
        isEmpty,
      );
      expect(
        reasons('services/edge.dart', '''
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
'''),
        isEmpty,
      );
      expect(
        reasons(
          'core/ui/glass_surface.dart',
          "import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';",
        ),
        isEmpty,
      );
    });

    test('a feature must not import another feature', () {
      expect(
        reasons('features/ask/a.dart', "import '../home/home_screen.dart';"),
        ['a feature must not import another feature'],
      );
    });

    test('a feature may import only the surface host from a2ui/', () {
      expect(
        reasons(
          'features/ask/a.dart',
          "import 'package:xpense_app/a2ui/catalog.dart';",
        ),
        ['features may import only a2ui/xpense_surface_host.dart from a2ui/'],
      );
    });

    test('a feature must not import Firestore, genkit or a2ui_core', () {
      for (final package in ['cloud_firestore', 'genkit', 'a2ui_core']) {
        expect(
          reasons(
            'features/ask/a.dart',
            "import 'package:$package/$package.dart';",
          ),
          contains('feature must not import $package'),
        );
      }
    });

    test('a2ui/ must not import features or Firestore', () {
      expect(reasons('a2ui/a.dart', "import '../features/ask/a.dart';"), [
        'a2ui must not import feature',
      ]);
      expect(
        reasons(
          'a2ui/a.dart',
          "import 'package:cloud_firestore/cloud_firestore.dart';",
        ),
        contains('a2ui must not import cloud_firestore'),
      );
    });

    test('data/ must not import features or Flutter widgets', () {
      expect(reasons('data/r.dart', "import '../features/ask/a.dart';"), [
        'data must not import feature',
      ]);
      expect(reasons('data/r.dart', "import 'package:flutter/widgets.dart';"), [
        'data must not import package:flutter/widgets.dart',
      ]);
      expect(
        reasons(
          'data/r.dart',
          "import 'package:material_ui/material_ui.dart';",
        ),
        ['data must not import material_ui'],
      );
    });

    test('services/ must not import features', () {
      expect(reasons('services/s.dart', "import '../features/ask/a.dart';"), [
        'services must not import feature',
      ]);
    });

    test('core/ must not import any layer above it', () {
      for (final target in [
        'features/ask/a.dart',
        'a2ui/a.dart',
        'data/r.dart',
        'services/s.dart',
      ]) {
        expect(
          reasons('core/c.dart', "import 'package:xpense_app/$target';"),
          hasLength(1),
          reason: target,
        );
      }
    });

    test('only a2ui/ may import the bundled Material library (D-22)', () {
      expect(
        reasons('core/c.dart', "import 'package:flutter/material.dart';"),
        ['core must not import package:flutter/material.dart'],
      );
      expect(reasons('main.dart', "import 'package:flutter/cupertino.dart';"), [
        'root must not import package:flutter/cupertino.dart',
      ]);
    });

    test('features import service interfaces, not implementations', () {
      const adapter = "import 'package:local_auth/local_auth.dart';";
      const interface =
          "import 'package:flutter_riverpod/flutter_riverpod.dart';";
      expect(
        isServiceImplementation('services/lock_local_auth.dart', adapter),
        isTrue,
      );
      expect(isServiceImplementation('services/lock.dart', interface), isFalse);
      expect(isServiceImplementation('services/lock_fake.dart', ''), isTrue);
      expect(isServiceImplementation('core/lock_fake.dart', adapter), isFalse);

      const reason =
          'features may import service interfaces only, not '
          'implementations or fakes';
      expect(
        reasons(
          'features/ask/a.dart',
          "import 'package:xpense_app/services/agent_client_fake.dart';",
        ),
        [reason],
      );
      expect(
        checkFile(
          'features/ask/a.dart',
          "import '../../services/lock_local_auth.dart';",
          serviceImplementations: {'services/lock_local_auth.dart'},
        ).map((v) => v.reason),
        [reason],
      );
      expect(
        reasons(
          'features/ask/a.dart',
          "import 'package:xpense_app/services/agent_client.dart';",
        ),
        isEmpty,
      );
      // The composition root wires implementations.
      expect(
        reasons(
          'bootstrap.dart',
          "import 'package:xpense_app/services/agent_client_fake.dart';",
        ),
        isEmpty,
      );
    });

    test('shared_preferences stays in services/', () {
      expect(
        reasons(
          'features/settings_privacy/s.dart',
          "import 'package:shared_preferences/shared_preferences.dart';",
        ),
        ['shared_preferences may only be imported in: services'],
      );
    });

    test('pre-1.0 and native packages stay in their adapter layer', () {
      expect(
        reasons(
          'core/c.dart',
          "import 'package:speech_to_text/speech_to_text.dart';",
        ),
        ['speech_to_text may only be imported in: services'],
      );
      expect(
        reasons(
          'services/s.dart',
          "import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';",
        ),
        ['liquid_glass_widgets may only be imported in: core'],
      );
      expect(
        reasons(
          'services/s.dart',
          "import 'package:a2ui_core/a2ui_core.dart';",
        ),
        ['a2ui_core may only be imported in: a2ui'],
      );
    });
  });
}
