/// Step 1 of the fast parser: normalisation (AI_PIPELINE 5).
library;

import 'package:meta/meta.dart';

/// Normalised text plus a case-preserving copy of the same length.
///
/// Every offset the parser reports refers to [text]. [cased] has exactly the
/// same characters except for case, so a span of [text] can be looked up in
/// [cased] to see whether the user wrote a capital (used for names).
@immutable
final class NormalizedText {
  /// Creates the pair. [text] and [cased] must have the same length.
  const new(this.text, this.cased)
    : assert(text.length == cased.length, 'cased must align with text');

  /// Trimmed, lower-case, single-spaced text with unified quotes and dashes.
  final String text;

  /// [text] with the original letter case.
  final String cased;

  @override
  bool operator ==(Object other) =>
      other is NormalizedText && other.text == text && other.cased == cased;

  @override
  int get hashCode => Object.hash(text, cased);

  @override
  String toString() => text;
}

const _singleQuotes = {0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x0060, 0x00B4};
const _doubleQuotes = {0x201C, 0x201D, 0x201E, 0x201F, 0x2033, 0x00AB, 0x00BB};
const _dashes = {0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212};
const _zeroWidth = {0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF, 0x00AD};

bool _isSpace(int rune) =>
    rune == 0x20 ||
    (rune >= 0x09 && rune <= 0x0D) ||
    rune == 0x85 ||
    rune == 0xA0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200A) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202F ||
    rune == 0x205F ||
    rune == 0x3000;

/// Normalises [raw]: trims, lower-cases, collapses whitespace to one space,
/// removes zero-width characters and unifies quote and dash variants to
/// `'`, `"` and `-`.
///
/// Total: any string is accepted. A character whose lower-case form has a
/// different length (rare outside English) keeps its original form, so the
/// result always aligns with [NormalizedText.cased].
NormalizedText normalize(String raw) {
  final lower = StringBuffer();
  final cased = StringBuffer();
  var pendingSpace = false;
  for (final rune in raw.runes) {
    if (_zeroWidth.contains(rune)) continue;
    if (_isSpace(rune)) {
      pendingSpace = lower.isNotEmpty;
      continue;
    }
    if (pendingSpace) {
      lower.write(' ');
      cased.write(' ');
      pendingSpace = false;
    }
    final unified = _singleQuotes.contains(rune)
        ? "'"
        : _doubleQuotes.contains(rune)
        ? '"'
        : _dashes.contains(rune)
        ? '-'
        : String.fromCharCode(rune);
    final lowered = unified.toLowerCase();
    lower.write(lowered.length == unified.length ? lowered : unified);
    cased.write(unified);
  }
  return NormalizedText(lower.toString(), cased.toString());
}

/// The normalised form of [raw] (see [normalize]).
String normalizeText(String raw) => normalize(raw).text;
