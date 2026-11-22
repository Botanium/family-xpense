/// Import-rule checker for the app's layers (ARCHITECTURE 3.1).
///
/// The rules are plain data so that the self-tests in
/// `import_rules_test.dart` can prove each one fires, and so that later work
/// packages can tighten them in one place. The checker reads source text
/// only; it does not need the analyzer, which keeps it fast enough to run
/// first in CI.
library;

import 'dart:io';

/// The package name used in `package:` imports of the app's own files.
const String appPackage = 'xpense_app';

/// A layer of `app/lib/`, decided by a file's path.
enum Layer {
  /// `lib/features/<name>/…`: screens and view models of one feature.
  feature,

  /// `lib/a2ui/…`: Xpense catalog widgets, surface host, action routing.
  a2ui,

  /// `lib/data/…`: Firestore repositories, DTO mapping, offline queue.
  data,

  /// `lib/services/…`: interfaces and implementations for native and remote.
  services,

  /// `lib/core/…`: theme, GlassSurface, formatting, l10n, routing, errors.
  core,

  /// Files directly in `lib/` (`main.dart`, `bootstrap.dart`, `app.dart`):
  /// the composition root, which wires every layer together.
  root,
}

/// Returns the layer of a file, given its path relative to `lib/`.
Layer layerOf(String libPath) {
  final first = libPath.split('/').first;
  return switch (first) {
    'features' => Layer.feature,
    'a2ui' => Layer.a2ui,
    'data' => Layer.data,
    'services' => Layer.services,
    'core' => Layer.core,
    _ => Layer.root,
  };
}

/// Returns the feature name of a path under `lib/features/`, or null.
String? featureOf(String libPath) {
  final parts = libPath.split('/');
  return parts.length > 2 && parts.first == 'features' ? parts[1] : null;
}

/// The only `a2ui/` file a feature may import: the surface host widget.
const String a2uiHostFile = 'a2ui/xpense_surface_host.dart';

/// Internal layers each layer must not import (the "Must not import" column
/// of ARCHITECTURE 3.1). Feature-to-feature and the a2ui host exception are
/// handled separately in [checkFile].
const Map<Layer, Set<Layer>> forbiddenLayers = {
  Layer.feature: {},
  Layer.a2ui: {Layer.feature},
  Layer.data: {Layer.feature},
  Layer.services: {Layer.feature},
  Layer.core: {Layer.feature, Layer.a2ui, Layer.data, Layer.services},
  Layer.root: {},
};

/// External packages each layer must not import, by package name.
const Map<Layer, Set<String>> forbiddenPackages = {
  Layer.feature: {'cloud_firestore', 'genkit', 'a2ui_core', 'a2ui_flutter'},
  Layer.a2ui: {'cloud_firestore'},
  Layer.data: {'material_ui', 'cupertino_ui'},
  Layer.services: {},
  Layer.core: {},
  Layer.root: {},
};

/// Flutter SDK libraries a layer must not import (`package:flutter/<lib>`).
///
/// `data/` must not depend on Flutter widgets. `flutter/material.dart` and
/// `flutter/cupertino.dart` are the deprecated bundled libraries: the app
/// uses `material_ui` and `cupertino_ui` (D-22), and only `a2ui/` may import
/// the bundled Material library, for the compatibility bridge that the
/// `a2ui_flutter 0.4.0` basic widgets need.
const Map<Layer, Set<String>> forbiddenFlutterLibraries = {
  Layer.feature: {'material.dart', 'cupertino.dart'},
  Layer.a2ui: {'cupertino.dart'},
  Layer.data: {
    'widgets.dart',
    'material.dart',
    'cupertino.dart',
    'rendering.dart',
    'painting.dart',
    'animation.dart',
    'gestures.dart',
  },
  Layer.services: {'material.dart', 'cupertino.dart'},
  Layer.core: {'material.dart', 'cupertino.dart'},
  Layer.root: {'material.dart', 'cupertino.dart'},
};

/// Pre-1.0, native or remote packages that only their adapter layer may
/// import (DELEGATION rule 7, ARCHITECTURE 3.2). A package matches by name
/// or by prefix followed by `_` (so `flutter_edge_ai` also covers
/// `flutter_edge_ai_litertlm`).
const Map<String, Set<Layer>> adapterOnlyPackages = {
  'a2ui_core': {Layer.a2ui},
  'a2ui_flutter': {Layer.a2ui},
  'liquid_glass_widgets': {Layer.core},
  'flutter_edge_ai': {Layer.services},
  'speech_to_text': {Layer.services},
  'google_mlkit_text_recognition': {Layer.services},
  'local_auth': {Layer.services},
  'flutter_secure_storage': {Layer.services},
  'genkit': {Layer.services},
  'cloud_firestore': {Layer.data, Layer.root},
};

/// One broken import rule.
class Violation {
  /// Creates a violation for [file] importing [uri].
  const new(this.file, this.uri, this.reason);

  /// The importing file, relative to `lib/`.
  final String file;

  /// The imported or exported URI as written.
  final String uri;

  /// Which rule was broken.
  final String reason;

  @override
  String toString() => 'lib/$file imports $uri: $reason';
}

final RegExp _directive = RegExp(
  r'^\s*(?:import|export)\s+([^;]+);',
  multiLine: true,
);
final RegExp _quoted = RegExp('''['"]([^'"]+)['"]''');

/// Returns every URI named by an import or export directive in [source],
/// including the URIs of conditional imports.
List<String> directiveUris(String source) => [
  for (final directive in _directive.allMatches(source))
    for (final quoted in _quoted.allMatches(directive.group(1)!))
      quoted.group(1)!,
];

/// Resolves [uri] imported from [fromLibPath] to a path relative to `lib/`,
/// or returns null when it points outside the app package.
String? resolveInternal(String fromLibPath, String uri) {
  if (uri.startsWith('package:$appPackage/')) {
    return uri.substring('package:$appPackage/'.length);
  }
  if (uri.contains(':')) return null;
  final resolved = Uri.parse('file:///lib/$fromLibPath').resolve(uri).path;
  return resolved.startsWith('/lib/') ? resolved.substring(5) : null;
}

/// Returns the package name of a `package:` URI, or null.
String? packageOf(String uri) {
  if (!uri.startsWith('package:')) return null;
  return uri.substring('package:'.length).split('/').first;
}

bool _matchesPackage(String package, String rule) =>
    package == rule || package.startsWith('${rule}_');

/// Checks one file, given its path relative to `lib/` and its source text.
List<Violation> checkFile(String libPath, String source) {
  final layer = layerOf(libPath);
  final violations = <Violation>[];
  for (final uri in directiveUris(source)) {
    final internal = resolveInternal(libPath, uri);
    if (internal != null) {
      final target = layerOf(internal);
      if (forbiddenLayers[layer]!.contains(target)) {
        violations.add(
          Violation(
            libPath,
            uri,
            '${layer.name} must not import ${target.name}',
          ),
        );
      }
      if (layer == Layer.feature) {
        final own = featureOf(libPath);
        final other = featureOf(internal);
        if (other != null && other != own) {
          violations.add(
            Violation(
              libPath,
              uri,
              'a feature must not import another feature',
            ),
          );
        }
        if (target == Layer.a2ui && internal != a2uiHostFile) {
          violations.add(
            Violation(
              libPath,
              uri,
              'features may import only $a2uiHostFile from a2ui/',
            ),
          );
        }
      }
      continue;
    }
    final package = packageOf(uri);
    if (package == null) continue;
    if (package == 'flutter') {
      final library = uri.substring('package:flutter/'.length);
      if (forbiddenFlutterLibraries[layer]!.contains(library)) {
        violations.add(
          Violation(libPath, uri, '${layer.name} must not import $uri'),
        );
      }
      continue;
    }
    for (final rule in forbiddenPackages[layer]!) {
      if (_matchesPackage(package, rule)) {
        violations.add(
          Violation(libPath, uri, '${layer.name} must not import $rule'),
        );
      }
    }
    for (final MapEntry(key: rule, value: allowed)
        in adapterOnlyPackages.entries) {
      if (_matchesPackage(package, rule) && !allowed.contains(layer)) {
        final where = allowed.map((l) => l.name).join(', ');
        violations.add(
          Violation(libPath, uri, '$rule may only be imported in: $where'),
        );
      }
    }
  }
  return violations;
}

/// Checks every Dart file under [libDir], skipping generated files.
List<Violation> checkLibrary(Directory libDir) {
  final violations = <Violation>[];
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'));
  for (final file in files) {
    final libPath = file.path
        .substring(libDir.path.length + 1)
        .replaceAll(r'\', '/');
    violations.addAll(checkFile(libPath, file.readAsStringSync()));
  }
  return violations;
}
