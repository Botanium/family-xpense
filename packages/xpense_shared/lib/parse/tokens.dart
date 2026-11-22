/// Tokens of normalised text, with offsets, shared by the parser steps.
library;

import 'package:meta/meta.dart';

/// What a [Token] is.
enum TokenKind {
  /// Letters, with inner apostrophes (`i'm`, `mcdonald's`).
  word,

  /// ASCII digits with inner `,` or `.` separators (`25,000`, `12.5`).
  number,

  /// Any other single non-space character (`$`, `?`, `/`).
  symbol,
}

/// One token of normalised text.
@immutable
final class Token {
  /// Creates a token covering `[start, end)` of the text.
  const new({
    required this.text,
    required this.kind,
    required this.start,
    required this.end,
    required this.glued,
  });

  /// The token text.
  final String text;

  /// The token kind.
  final TokenKind kind;

  /// Start offset in the normalised text.
  final int start;

  /// End offset (exclusive) in the normalised text.
  final int end;

  /// Whether the token touches the previous one with no space (`5` `k` in
  /// `5k`).
  final bool glued;

  /// Whether this is a word token.
  bool get isWord => kind == TokenKind.word;

  /// Whether this is a number token.
  bool get isNumber => kind == TokenKind.number;

  /// Whether this is a symbol token.
  bool get isSymbol => kind == TokenKind.symbol;

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.text == text &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.glued == glued;

  @override
  int get hashCode => Object.hash(text, kind, start, end, glued);

  @override
  String toString() => '$kind($text@$start)';
}

final _tokenPattern = RegExp(
  r"(\p{L}(?:[\p{L}']*\p{L})?)|([0-9]+(?:[.,][0-9]+)*)|(\S)",
  unicode: true,
);

/// Splits normalised [text] into tokens. Total; spaces produce no token.
List<Token> tokenize(String text) {
  final tokens = <Token>[];
  var previousEnd = -1;
  for (final match in _tokenPattern.allMatches(text)) {
    final kind = match.group(1) != null
        ? TokenKind.word
        : match.group(2) != null
        ? TokenKind.number
        : TokenKind.symbol;
    tokens.add(
      Token(
        text: match.group(0)!,
        kind: kind,
        start: match.start,
        end: match.end,
        glued: match.start == previousEnd,
      ),
    );
    previousEnd = match.end;
  }
  return tokens;
}

/// The token-index ranges where the space-separated [phrase] occurs in
/// [tokens], as `(start, end)` pairs with `end` exclusive, left to right.
///
/// A phrase token matches a token with the same text. Overlapping matches
/// are all returned.
List<(int, int)> findPhraseTokens(List<Token> tokens, String phrase) {
  final parts = tokenize(phrase).map((t) => t.text).toList();
  if (parts.isEmpty) return const [];
  final found = <(int, int)>[];
  for (var i = 0; i + parts.length <= tokens.length; i++) {
    var ok = true;
    for (var j = 0; j < parts.length; j++) {
      if (tokens[i + j].text != parts[j]) {
        ok = false;
        break;
      }
    }
    if (ok) found.add((i, i + parts.length));
  }
  return found;
}

/// Whether [tokens] from index [at] start with the phrase [phrase].
bool phraseAt(List<Token> tokens, int at, String phrase) {
  final parts = tokenize(phrase).map((t) => t.text).toList();
  if (parts.isEmpty || at < 0 || at + parts.length > tokens.length) {
    return false;
  }
  for (var j = 0; j < parts.length; j++) {
    if (tokens[at + j].text != parts[j]) return false;
  }
  return true;
}

final _wordChar = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The start offsets of whole-word occurrences of [phrase] in [text]: the
/// characters before and after the match must not be letters or digits.
///
/// Both strings are expected to be normalised. An empty phrase matches
/// nowhere.
List<int> findWholeWord(String text, String phrase) {
  if (phrase.isEmpty) return const [];
  final starts = <int>[];
  var from = 0;
  while (true) {
    final at = text.indexOf(phrase, from);
    if (at < 0) break;
    final end = at + phrase.length;
    final beforeOk = at == 0 || !_wordChar.hasMatch(text[at - 1]);
    final afterOk = end == text.length || !_wordChar.hasMatch(text[end]);
    if (beforeOk && afterOk) starts.add(at);
    from = at + 1;
  }
  return starts;
}
