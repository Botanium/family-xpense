/// Raw-value gate (DESIGN_SYSTEM 2, DELEGATION rule 6).
///
/// No raw colour, radius, duration, curve or font size outside
/// `lib/core/theme/`, and only directional insets and alignments anywhere
/// (DESIGN_SYSTEM 10). The rules are data so the self-tests can prove each
/// one fires. Runs in CI as part of `flutter test`.
library;

import 'dart:io';

/// The only folder allowed to hold raw design values, relative to `lib/`.
const String themeFolder = 'core/theme/';

/// One forbidden pattern.
class RawRule {
  /// Creates a rule.
  const new(this.name, this.pattern, {this.everywhere = false});

  /// What the rule forbids.
  final String name;

  /// Matches the forbidden text on one line.
  final RegExp pattern;

  /// Whether the rule applies inside [themeFolder] too.
  final bool everywhere;
}

/// The rules.
final List<RawRule> rawRules = [
  RawRule('raw colour', RegExp(r'\bColor\s*\(\s*0x')),
  RawRule('raw colour', RegExp(r'\bColor\.from(ARGB|RGBO)\s*\(')),
  RawRule('Material colour constant', RegExp(r'\bColors\.\w')),
  RawRule('Cupertino colour constant', RegExp(r'\bCupertinoColors\.\w')),
  RawRule(
    'raw radius',
    RegExp(r'\bRadius\.(circular|elliptical)\s*\(\s*[\d.]'),
  ),
  RawRule(
    'raw radius',
    RegExp(r'\bBorderRadius(Directional)?\.circular\s*\(\s*[\d.]'),
  ),
  RawRule(
    'raw duration',
    RegExp(
      r'\bDuration\s*\(\s*(milli|micro|)seconds|\bDuration\s*\(\s*(minutes|hours|days)',
    ),
  ),
  RawRule('raw curve', RegExp(r'\bCurves\.\w')),
  RawRule('raw font size', RegExp(r'\bfontSize\s*:')),
  RawRule('google_fonts', RegExp('package:google_fonts/'), everywhere: true),
  RawRule(
    'seeded colour scheme',
    RegExp(r'ColorScheme\.fromSeed'),
    everywhere: true,
  ),
  RawRule(
    'non-directional insets',
    RegExp(r'\bEdgeInsets\.(only|fromLTRB)\s*\('),
    everywhere: true,
  ),
  RawRule(
    'non-directional alignment',
    RegExp(
      r'\bAlignment\.(topLeft|topRight|centerLeft|centerRight|bottomLeft|bottomRight)\b',
    ),
    everywhere: true,
  ),
  RawRule(
    'non-directional border radius',
    RegExp(r'\bBorderRadius\.(only|horizontal)\s*\('),
    everywhere: true,
  ),
  RawRule(
    'non-directional text alignment',
    RegExp(r'\bTextAlign\.(left|right)\b'),
    everywhere: true,
  ),
  RawRule(
    'non-directional Positioned',
    RegExp(r'\bPositioned\s*\([^)]*\b(left|right)\s*:'),
    everywhere: true,
  ),
];

/// One broken rule.
class RawViolation {
  /// Creates a violation.
  const new(this.file, this.line, this.rule, this.text);

  /// File relative to `lib/`.
  final String file;

  /// 1-based line number.
  final int line;

  /// Rule name.
  final String rule;

  /// The offending line.
  final String text;

  @override
  String toString() => 'lib/$file:$line $rule: ${text.trim()}';
}

/// Checks one file's [source], given its path relative to `lib/`.
List<RawViolation> checkSource(String libPath, String source) {
  final inTheme = libPath.startsWith(themeFolder);
  final violations = <RawViolation>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final code = line.split('//').first;
    if (code.trim().isEmpty) continue;
    for (final rule in rawRules) {
      if (inTheme && !rule.everywhere) continue;
      if (rule.pattern.hasMatch(code)) {
        violations.add(RawViolation(libPath, i + 1, rule.name, line));
      }
    }
  }
  return violations;
}

/// Checks every Dart file under [libDir], skipping generated files.
List<RawViolation> checkRawValues(Directory libDir) {
  final violations = <RawViolation>[];
  final files =
      libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('.g.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final libPath = file.path
        .substring(libDir.path.length + 1)
        .replaceAll(r'\', '/');
    violations.addAll(checkSource(libPath, file.readAsStringSync()));
  }
  return violations;
}
