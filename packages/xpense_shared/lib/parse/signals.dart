/// The router's complexity signals (AI_PIPELINE 2) and the explicit intent
/// words the fast parser reads.
library;

import 'package:meta/meta.dart';
import 'package:xpense_shared/parse/amounts.dart';
import 'package:xpense_shared/parse/hints.dart';
import 'package:xpense_shared/parse/lexicon.dart';
import 'package:xpense_shared/parse/normalize.dart';
import 'package:xpense_shared/parse/tokens.dart';
import 'package:xpense_shared/schema/parse_result.dart';
import 'package:xpense_shared/taxonomy/intents.dart';

/// The attachment of a captured message; [wire] is the schema value.
enum Attachment {
  /// Text only.
  none('none'),

  /// Audio with no on-device transcript.
  audio('audio'),

  /// An image (receipt).
  image('image');

  new(this.wire);

  /// The schema value.
  final String wire;
}

/// A required field the parser could not settle; [wire] is the schema
/// value (`unresolvedFieldValues`).
enum UnresolvedField {
  /// The category (required for expense and income).
  category('category'),

  /// The account.
  account('account'),

  /// The intent.
  intent('intent');

  new(this.wire);

  /// The schema value.
  final String wire;
}

/// The complexity signals of one message (AI_PIPELINE 2).
@immutable
final class Signals {
  /// Creates the signals.
  const new({
    required this.amountCount,
    required this.hasConjunction,
    required this.isQuestion,
    required this.isCommand,
    required this.hasPersonTransfer,
    required this.unresolved,
    required this.attachment,
  });

  /// Number of amounts found.
  final int amountCount;

  /// A conjunction joins clauses that each hold an amount or a verb.
  final bool hasConjunction;

  /// The message asks about data.
  final bool isQuestion;

  /// The message is a command.
  final bool isCommand;

  /// Money went to or came from a named person.
  final bool hasPersonTransfer;

  /// Required fields still missing after rules, in schema order.
  final List<UnresolvedField> unresolved;

  /// The attachment type.
  final Attachment attachment;

  /// The schema form.
  ComplexitySignals toSchema() => ComplexitySignals(
    amountCount: amountCount,
    hasConjunction: hasConjunction,
    isQuestion: isQuestion,
    isCommand: isCommand,
    hasPersonTransfer: hasPersonTransfer,
    unresolved: [for (final f in unresolved) f.wire],
    attachment: attachment.wire,
  );

  @override
  bool operator ==(Object other) =>
      other is Signals &&
      other.amountCount == amountCount &&
      other.hasConjunction == hasConjunction &&
      other.isQuestion == isQuestion &&
      other.isCommand == isCommand &&
      other.hasPersonTransfer == hasPersonTransfer &&
      _sameList(other.unresolved, unresolved) &&
      other.attachment == attachment;

  @override
  int get hashCode => Object.hash(
    amountCount,
    hasConjunction,
    isQuestion,
    isCommand,
    hasPersonTransfer,
    Object.hashAll(unresolved),
    attachment,
  );

  @override
  String toString() =>
      'Signals(amounts: $amountCount, conj: $hasConjunction, '
      'q: $isQuestion, cmd: $isCommand, person: $hasPersonTransfer, '
      'unresolved: ${unresolved.map((f) => f.wire)}, ${attachment.wire})';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The index of the first token after politeness openers (`please`,
/// `can you`).
int skipPolite(List<Token> tokens, ParserLexicon lex) {
  var at = 0;
  var moved = true;
  while (moved) {
    moved = false;
    for (final phrase in lex.politePrefixes) {
      if (phraseAt(tokens, at, phrase)) {
        at += tokenize(phrase).length;
        moved = true;
      }
    }
    if (at < tokens.length && tokens[at].text == ',') {
      at++;
      moved = true;
    }
  }
  return at;
}

/// Whether the message asks about data: a `?`, a question phrase anywhere
/// (`how much`, `what`, `which`), or a question word opening the message.
bool detectQuestion(
  String text,
  List<Token> tokens, [
  ParserLexicon lex = englishLexicon,
]) {
  if (text.contains('?')) return true;
  for (final phrase in lex.questionPhrases) {
    if (findWholeWord(text, phrase).isNotEmpty) return true;
  }
  final at = skipPolite(tokens, lex);
  return at < tokens.length && lex.questionLeads.contains(tokens[at].text);
}

/// Whether the message is a command: an imperative verb opening it
/// (after `please`, `can you`), or a command phrase anywhere (`set budget`,
/// `new goal`).
bool detectCommand(
  String text,
  List<Token> tokens, [
  ParserLexicon lex = englishLexicon,
]) {
  for (final phrase in lex.commandPhrases) {
    if (findWholeWord(text, phrase).isNotEmpty) return true;
  }
  final at = skipPolite(tokens, lex);
  return at < tokens.length && lex.commandLeads.contains(tokens[at].text);
}

/// Whether a conjunction joins two clauses that each hold an amount or an
/// activity verb (AI_PIPELINE 2): `salary 3,200 and rent 1,400` yes,
/// `bread and milk 5000` no.
///
/// Conjunction tokens whose index is in [ignored] (inside an amount such as
/// `one and a half million`, a date or a name) do not split clauses.
bool detectConjunction(
  List<Token> tokens,
  List<AmountMention> amounts, {
  Set<int> ignored = const {},
  ParserLexicon lexicon = englishLexicon,
}) {
  final lex = lexicon;
  final amountTokens = <int>{
    for (final a in amounts)
      for (var k = a.tokenStart; k < a.tokenEnd; k++) k,
  };
  final splits = [
    for (var k = 0; k < tokens.length; k++)
      if (lex.conjunctions.contains(tokens[k].text) &&
          !ignored.contains(k) &&
          !amountTokens.contains(k))
        k,
  ];
  bool holds(int from, int to) {
    if (from >= to) return false;
    for (final a in amounts) {
      if (a.tokenStart >= from && a.tokenStart < to) return true;
    }
    for (var k = from; k < to; k++) {
      if (lex.activityVerbs.contains(tokens[k].text)) return true;
    }
    return false;
  }

  for (var s = 0; s < splits.length; s++) {
    final from = s == 0 ? 0 : splits[s - 1] + 1;
    final to = s + 1 < splits.length ? splits[s + 1] : tokens.length;
    if (holds(from, splits[s]) && holds(splits[s] + 1, to)) return true;
  }
  return false;
}

/// Token ranges of the lexicon's transfer verbs in [tokens].
List<(int, int)> findTransferVerbs(
  List<Token> tokens, [
  ParserLexicon lex = englishLexicon,
]) => [
  for (final phrase in lex.transferVerbs) ...findPhraseTokens(tokens, phrase),
];

/// Whether [word] belongs to any of the lexicon's tables, so it is not a
/// name.
bool isLexiconWord(String word, ParserLexicon lex) =>
    lex.stopWords.contains(word) ||
    lex.units.containsKey(word) ||
    lex.tens.containsKey(word) ||
    lex.scaleWords.containsKey(word) ||
    lex.currencyWords.containsKey(word) ||
    lex.minorUnitWords.containsKey(word) ||
    lex.activityVerbs.contains(word) ||
    lex.conjunctions.contains(word) ||
    lex.questionLeads.contains(word) ||
    lex.commandLeads.contains(word) ||
    lex.relationWords.contains(word) ||
    lex.weekdays.containsKey(word) ||
    lex.months.containsKey(word) ||
    lex.accountWords.containsKey(word) ||
    lex.quantityUnits.contains(word) ||
    lex.transferVerbs.any((p) => p.split(' ').contains(word)) ||
    lex.intentCues.keys.any((p) => p.split(' ').contains(word));

/// Capitalised words near a transfer verb that are not known words: names
/// the household has not saved yet (`gave Alex 300`).
///
/// Uses [NormalizedText.cased] to see the capital. Words inside [taken]
/// spans (already matched hints) are skipped. Each name becomes an
/// unresolved person hint.
List<HintMatch> findUnknownNames(
  NormalizedText normalized,
  List<Token> tokens,
  List<(int, int)> transferVerbs, {
  List<(int, int)> taken = const [],
  ParserLexicon lexicon = englishLexicon,
}) {
  final lex = lexicon;
  final names = <HintMatch>[];
  final seen = <int>{};
  for (final (from, to) in transferVerbs) {
    final lo = (from - 5).clamp(0, tokens.length);
    final hi = (to + 5).clamp(0, tokens.length);
    for (var k = lo; k < hi; k++) {
      if (k >= from && k < to) continue;
      final token = tokens[k];
      if (!token.isWord || seen.contains(k)) continue;
      final first = normalized.cased[token.start];
      if (first == first.toLowerCase()) continue;
      if (isLexiconWord(token.text, lex)) continue;
      if (taken.any((t) => token.start < t.$2 && token.end > t.$1)) continue;
      seen.add(k);
      names.add(
        HintMatch(
          kind: HintKind.person,
          span: token.text,
          start: token.start,
          end: token.end,
          confidence: unresolvedHintConfidence,
        ),
      );
    }
  }
  names.sort((a, b) => a.start.compareTo(b.start));
  return names;
}

/// Whether money went to or came from a named person: a transfer verb
/// (`gave`, `lent`, `paid back`, `owes`) plus a name, where a name is a
/// person hint (saved or new) or a relation word (`dad`).
bool detectPersonTransfer(
  List<Token> tokens,
  List<HintMatch> hints, {
  ParserLexicon lexicon = englishLexicon,
}) {
  final lex = lexicon;
  if (findTransferVerbs(tokens, lex).isEmpty) return false;
  if (hints.any((h) => h.kind == HintKind.person)) return true;
  return tokens.any((t) => lex.relationWords.contains(t.text));
}

/// The intent the message states in so many words, or `null` when it
/// states none or several disagree.
///
/// Cue phrases (`spent`, `lent`, `paid me back`) are matched longest
/// first without overlap. A bare `paid` counts as an expense only when no
/// person is named (`paid Alex 300` may be a loan repayment or a gift).
/// `gave` is never a cue: the `repayable` question settles it.
CaptureIntent? detectIntentCue(
  List<Token> tokens, {
  required bool personNamed,
  ParserLexicon lexicon = englishLexicon,
}) {
  final lex = lexicon;
  final cues = lex.intentCues.keys.toList()
    ..sort((a, b) => b.split(' ').length.compareTo(a.split(' ').length));
  final used = <int>{};
  final intents = <String>{};
  for (final cue in cues) {
    for (final (from, to) in findPhraseTokens(tokens, cue)) {
      final overlaps = Iterable<int>.generate(
        to - from,
        (k) => from + k,
      ).any(used.contains);
      if (overlaps) {
        continue;
      }
      for (var k = from; k < to; k++) {
        used.add(k);
      }
      intents.add(lex.intentCues[cue]!);
    }
  }
  if (!personNamed) {
    for (var k = 0; k < tokens.length; k++) {
      if (!used.contains(k) && lex.payWords.contains(tokens[k].text)) {
        intents.add(CaptureIntent.expense.wire);
      }
    }
  }
  if (intents.length != 1) return null;
  return CaptureIntent.tryParse(intents.single);
}
