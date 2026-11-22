/// Step 6 of the fast parser: account, person, category and who hints
/// (AI_PIPELINE 5).
library;

import 'package:meta/meta.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/parse/lexicon.dart';
import 'package:xpense_shared/parse/normalize.dart';
import 'package:xpense_shared/parse/tokens.dart';

/// Confidence of a hint matched on an account or person name or alias.
const double nameHintConfidence = 0.9;

/// Confidence of a generic account word that points at exactly one account
/// (`cash` when the household has one cash account).
const double genericAccountConfidence = 0.8;

/// Confidence of a category hint matched on a category name. Kept below
/// the "settled" level: a category word in the text is evidence, not a
/// decision (`water` may be the bill or a bottle).
const double categoryHintConfidence = 0.75;

/// Confidence of a `joint` who hint.
const double jointWhoConfidence = 0.8;

/// Confidence of a `partner` who hint.
const double partnerWhoConfidence = 0.6;

/// Confidence of a hint that matched words but no single target.
const double unresolvedHintConfidence = 0.5;

/// An account the household can see (DATA_MODEL 2.4), as the parser needs
/// it.
@immutable
final class ParserAccount {
  /// Creates an account entry.
  const new({
    required this.id,
    required this.name,
    required this.currency,
    this.kind = 'other',
    this.aliases = const [],
  });

  /// The account id.
  final String id;

  /// The account name, for example `Cash wallet`.
  final String name;

  /// The account currency.
  final Currency currency;

  /// The account kind: `cash`, `bank`, `credit`, `savings` or `other`.
  final String kind;

  /// Other names the household uses for the account.
  final List<String> aliases;
}

/// A person (DATA_MODEL 2.7), as the parser needs it.
@immutable
final class ParserPerson {
  /// Creates a person entry.
  const new({required this.id, required this.name, this.aliases = const []});

  /// The person id.
  final String id;

  /// The person's name.
  final String name;

  /// Other names for the person.
  final List<String> aliases;
}

/// A category (DATA_MODEL 2.6), as the parser needs it.
@immutable
final class ParserCategory {
  /// Creates a category entry.
  const new({
    required this.id,
    required this.names,
    this.kind = 'expense',
    this.aliases = const [],
  });

  /// The category id.
  final String id;

  /// Names by language code (`{'en': 'Groceries'}`).
  final Map<String, String> names;

  /// `expense` or `income`.
  final String kind;

  /// Other words for the category.
  final List<String> aliases;
}

/// What a [HintMatch] points at; [wire] is the `ParseHint.kind` value.
enum HintKind {
  /// An account.
  account('account'),

  /// A person.
  person('person'),

  /// A category.
  category('category'),

  /// Whose money it is.
  who('who');

  new(this.wire);

  /// The schema value.
  final String wire;
}

/// A hint found in the text.
@immutable
final class HintMatch {
  /// Creates a hint covering `[start, end)` of the normalised text.
  const new({
    required this.kind,
    required this.span,
    required this.start,
    required this.end,
    required this.confidence,
    this.id,
    this.who,
    this.currency,
  });

  /// What the hint points at.
  final HintKind kind;

  /// The matched text.
  final String span;

  /// Start offset in the normalised text.
  final int start;

  /// End offset (exclusive) in the normalised text.
  final int end;

  /// Confidence, 0 to 1.
  final double confidence;

  /// The resolved account, person or category id.
  final String? id;

  /// The `who` value for who hints (`partner`, `joint`).
  final String? who;

  /// The resolved account's currency (account hints only).
  final Currency? currency;

  /// Whether the hint resolved to one target.
  bool get isResolved => id != null || who != null;

  @override
  bool operator ==(Object other) =>
      other is HintMatch &&
      other.kind == kind &&
      other.span == span &&
      other.start == start &&
      other.end == end &&
      other.confidence == confidence &&
      other.id == id &&
      other.who == who &&
      other.currency == currency;

  @override
  int get hashCode =>
      Object.hash(kind, span, start, end, confidence, id, who, currency);

  @override
  String toString() => 'HintMatch(${kind.wire} "$span" → ${id ?? who})';
}

final class _Candidate {
  new(this.phrase, this.kind, this.id, this.currency);
  final String phrase;
  final HintKind kind;
  final String id;
  final Currency? currency;
}

/// Finds hints in normalised [text], ordered by position.
///
/// Names and aliases of [accounts], [people] and [categories] are matched
/// as whole words, longest first, without overlap. A phrase shared by two
/// targets of the same kind gives an unresolved hint. Then the lexicon's
/// generic account words (`cash`, `visa`) resolve to the one account whose
/// name holds the word, else the one account of the matching kind, else
/// stay unresolved. Then who words (`joint`, `my wife`).
List<HintMatch> findHints(
  String text, {
  List<ParserAccount> accounts = const [],
  List<ParserPerson> people = const [],
  List<ParserCategory> categories = const [],
  ParserLexicon lexicon = englishLexicon,
}) {
  final lex = lexicon;
  final candidates =
      <_Candidate>[
          for (final a in accounts)
            for (final phrase in [a.name, ...a.aliases])
              _Candidate(
                normalizeText(phrase),
                HintKind.account,
                a.id,
                a.currency,
              ),
          for (final p in people)
            for (final phrase in [p.name, ...p.aliases])
              _Candidate(normalizeText(phrase), HintKind.person, p.id, null),
          for (final c in categories)
            for (final phrase in [
              c.names[lex.languageCode] ?? c.names['en'] ?? '',
              ...c.aliases,
            ])
              _Candidate(normalizeText(phrase), HintKind.category, c.id, null),
        ]
        ..removeWhere((c) => c.phrase.isEmpty)
        ..sort((a, b) => b.phrase.length.compareTo(a.phrase.length));

  final hints = <HintMatch>[];
  final taken = <(int, int)>[];
  bool free(int s, int e) => taken.every((t) => e <= t.$1 || s >= t.$2);

  // Group candidates by phrase so shared phrases become unresolved hints.
  final byPhrase = <String, List<_Candidate>>{};
  for (final c in candidates) {
    byPhrase.putIfAbsent(c.phrase, () => []).add(c);
  }
  for (final entry in byPhrase.entries) {
    final phrase = entry.key;
    for (final at in findWholeWord(text, phrase)) {
      final end = at + phrase.length;
      if (!free(at, end)) continue;
      final kinds = {for (final c in entry.value) c.kind};
      // When the same phrase names targets of several kinds, the first
      // kind in enum order wins (account, person, category).
      final kind = HintKind.values.firstWhere(kinds.contains);
      final targets = {
        for (final c in entry.value)
          if (c.kind == kind) c.id: c,
      };
      final single = targets.length == 1 ? targets.values.single : null;
      hints.add(
        HintMatch(
          kind: kind,
          span: phrase,
          start: at,
          end: end,
          confidence: single == null
              ? unresolvedHintConfidence
              : kind == HintKind.category
              ? categoryHintConfidence
              : nameHintConfidence,
          id: single?.id,
          currency: single?.currency,
        ),
      );
      taken.add((at, end));
    }
  }

  final accountWords = lex.accountWords.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final word in accountWords) {
    for (final at in findWholeWord(text, word)) {
      final end = at + word.length;
      if (!free(at, end)) continue;
      final account = _resolveGeneric(word, lex.accountWords[word]!, accounts);
      hints.add(
        HintMatch(
          kind: HintKind.account,
          span: word,
          start: at,
          end: end,
          confidence: account == null
              ? unresolvedHintConfidence
              : genericAccountConfidence,
          id: account?.id,
          currency: account?.currency,
        ),
      );
      taken.add((at, end));
    }
  }

  final whoWords = lex.whoWords.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final word in whoWords) {
    for (final at in findWholeWord(text, word)) {
      final end = at + word.length;
      if (!free(at, end)) continue;
      final who = lex.whoWords[word]!;
      hints.add(
        HintMatch(
          kind: HintKind.who,
          span: word,
          start: at,
          end: end,
          confidence: who == 'joint'
              ? jointWhoConfidence
              : partnerWhoConfidence,
          who: who,
        ),
      );
      taken.add((at, end));
    }
  }

  hints.sort((a, b) => a.start.compareTo(b.start));
  return hints;
}

ParserAccount? _resolveGeneric(
  String word,
  List<String> kinds,
  List<ParserAccount> accounts,
) {
  final byName = [
    for (final a in accounts)
      if ([
        a.name,
        ...a.aliases,
      ].any((n) => findWholeWord(normalizeText(n), word).isNotEmpty))
        a,
  ];
  if (byName.length == 1) return byName.single;
  if (byName.length > 1) return null;
  final byKind = [
    for (final a in accounts)
      if (kinds.contains(a.kind)) a,
  ];
  return byKind.length == 1 ? byKind.single : null;
}
