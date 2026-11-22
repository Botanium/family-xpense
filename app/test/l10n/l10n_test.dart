import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// String gates (DELEGATION rule 6, DESIGN_SYSTEM 10): every user-facing
/// string comes from `lib/l10n/app_en.arb`, keys start with the feature
/// that owns them, and every key tells translators what it is.
void main() {
  final arb = jsonDecode(
    File('lib/l10n/app_en.arb').readAsStringSync(),
  ) as Map<String, Object?>;
  final keys = arb.keys.where((k) => !k.startsWith('@')).toList();

  group('app_en.arb', () {
    test('every key starts with the area that owns it', () {
      // Core areas, then one prefix per feature folder: its first word,
      // such as `settings` for `settings_privacy`.
      final prefixes = {
        'app',
        'shell',
        'routing',
        'lock',
        for (final dir in Directory('lib/features').listSync())
          if (dir is Directory)
            dir.uri.pathSegments.reversed.skip(1).first.split('_').first,
      };
      final unowned = [
        for (final key in keys)
          if (!prefixes.any(
            (p) => key.startsWith(p) && _isUpper(key, p.length),
          ))
            key,
      ];
      expect(unowned, isEmpty, reason: 'Known prefixes: $prefixes');
    });

    test('every key has a description for translators', () {
      final missing = [
        for (final key in keys)
          if ((arb['@$key'] as Map<String, Object?>?)?['description'] == null)
            key,
      ];
      expect(missing, isEmpty);
    });
  });

  group('hard-coded strings', () {
    test('no UI text outside the ARB file', () {
      final violations = hardCodedStrings(Directory('lib'));
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('the check finds text and ignores what is not language', () {
      expect(findHardCoded("Text('Hello')"), isNotEmpty);
      expect(findHardCoded("semanticLabel: 'Back'"), isNotEmpty);
      expect(findHardCoded('label: "Save",'), isNotEmpty);
      expect(findHardCoded("placeholder: '0'"), isEmpty);
      expect(findHardCoded(r"Text('“$text”')"), isEmpty);
      expect(findHardCoded('Text(l10n.homeTitle)'), isEmpty);
      expect(findHardCoded("// Text('comment')"), isEmpty);
    });
  });
}

bool _isUpper(String key, int index) =>
    index < key.length && key[index] == key[index].toUpperCase();

final RegExp _uiString = RegExp(
  r'''(?:\b(?:Text|TextSpan)\(\s*|\b(?:label|semanticLabel|title|message|hint|tooltip|actionLabel|unlockLabel|subtitle|placeholder|localizedReason|reason)\s*:\s*)(['"])(.*?)\1''',
);
final RegExp _interpolation = RegExp(r'\$\{[^}]*\}|\$\w+');
final RegExp _letter = RegExp(r'\p{L}', unicode: true);

/// Returns the UI string literals with words in one line of [source].
List<String> findHardCoded(String source) => [
  for (final line in source.split('\n'))
    for (final match in _uiString.allMatches(line.split('//').first))
      if (_letter.hasMatch(match.group(2)!.replaceAll(_interpolation, '')))
        match.group(0)!,
];

/// Checks every hand-written Dart file under [lib]. The debug-only gallery
/// is developer-facing and exempt; generated files are skipped.
List<String> hardCodedStrings(Directory lib) => [
  for (final file in lib.listSync(recursive: true).whereType<File>())
    if (file.path.endsWith('.dart') &&
        !file.path.contains('/generated/') &&
        !file.path.contains('/core/ui/gallery/') &&
        !file.path.endsWith('.g.dart'))
      for (final hit in findHardCoded(file.readAsStringSync()))
        '${file.path}: $hit',
];
