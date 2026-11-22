/// The classification step (AI_PIPELINE 7) as one interface.
///
/// `/v1/decide` (the phone) and the agent's `prepareEntries` tool (WP-32)
/// both classify a single-entry message through [EntryClassifier]. The real
/// implementation builds the question set from the household's own
/// categories, accounts, members and people, calls the Decisions API and
/// applies the fallback chain; tests and the agent's own tests use
/// [FakeEntryClassifier].
library;

import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// One Decisions question key (AI_PIPELINE 7). [key] is the wire name used
/// in `DecideRequest.ask` and as the `DecideResponse` field.
enum DecideQuestion {
  /// What kind of money event: one of the 12 intents.
  intent('intent'),

  /// The household category.
  category('category'),

  /// The account the money left from or arrived in.
  account('account'),

  /// The destination account of a transfer or savings move.
  toAccount('to_account'),

  /// Whose spending or income: me, partner, joint.
  who('who'),

  /// The household's person a loan, repayment or gift is with.
  person('person'),

  /// Whether the message holds more than one money event.
  multiEntry('multi_entry'),

  /// Whether money to or from a person is to be paid back.
  repayable('repayable'),

  /// Whether essential information is missing or ambiguous.
  needsFollowup('needs_followup'),

  /// Whether the payment or income normally repeats.
  isRecurring('is_recurring'),

  /// Whether the message is a recent entry saved again. Asked only when
  /// deterministic candidates exist.
  duplicate('duplicate');

  new(this.key);

  /// The wire name.
  final String key;

  /// The question for [key], or null for an unknown key.
  static DecideQuestion? byKey(String key) {
    for (final q in values) {
      if (q.key == key) return q;
    }
    return null;
  }
}

/// Classifies one single-entry message for one household.
abstract interface class EntryClassifier {
  /// Answers the questions in [ask] about [text] for the household and
  /// speaker in [context].
  ///
  /// [parsed] and [hints] are what the fast parser settled; an account hint
  /// with an id narrows the duplicate search. Duplicate candidates are found
  /// on the server only, among the saved entries the speaker can see;
  /// `duplicate` is asked only when there is at least one. [candidates] is
  /// kept for compatibility with `DecideRequest` and is ignored. [lang] is
  /// `en` for now.
  ///
  /// Each asked question that got an answer is set on the response; others
  /// are absent. Answers from the uncalibrated fallback carry
  /// `calibrated: false`. When no classifier could answer (blocked input,
  /// outage, switch off) the response is `{unavailable: true}`. It never
  /// throws for upstream failures, only for programming errors.
  Future<DecideResponse> classify({
    required XpenseContext context,
    required String text,
    required Set<DecideQuestion> ask,
    DecideParsed? parsed,
    List<ParseHint> hints = const [],
    List<DuplicateCandidate> candidates = const [],
    String lang = 'en',
  });
}

/// One call recorded by [FakeEntryClassifier].
typedef ClassifyCall = ({
  XpenseContext context,
  String text,
  Set<DecideQuestion> ask,
  DecideParsed? parsed,
  List<ParseHint> hints,
  List<DuplicateCandidate> candidates,
});

/// An [EntryClassifier] for tests: answers with `respond`, by default
/// `{unavailable: true}`, and records every call.
final class FakeEntryClassifier implements EntryClassifier {
  /// Creates a fake. `respond` computes the answer for one call.
  new({DecideResponse Function(ClassifyCall call)? respond})
    : _respond = respond ?? ((_) => DecideResponse(unavailable: true));

  /// A fake that answers every call with [response].
  factory always(DecideResponse response) =>
      FakeEntryClassifier(respond: (_) => response);

  final DecideResponse Function(ClassifyCall call) _respond;

  /// The calls received, in order.
  final List<ClassifyCall> calls = [];

  @override
  Future<DecideResponse> classify({
    required XpenseContext context,
    required String text,
    required Set<DecideQuestion> ask,
    DecideParsed? parsed,
    List<ParseHint> hints = const [],
    List<DuplicateCandidate> candidates = const [],
    String lang = 'en',
  }) async {
    final call = (
      context: context,
      text: text,
      ask: ask,
      parsed: parsed,
      hints: hints,
      candidates: candidates,
    );
    calls.add(call);
    return _respond(call);
  }
}
