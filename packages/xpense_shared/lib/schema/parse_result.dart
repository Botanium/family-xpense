import 'package:schemantic/schemantic.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/schema/wire_values.dart';

part 'parse_result.g.dart';

/// Output of the on-device fast parser (AI_PIPELINE 5, step 8):
/// `{amounts[], currency?, date, hints, ruleHits, signals}`.
///
/// The parser itself is WP-30 (`lib/parse/`); this is its contract.
@Schema(description: 'Output of the deterministic fast parser.')
abstract class $ParseResult {
  /// Every amount found, in message order.
  List<$ParsedAmount>? get amounts;

  /// The message-level currency, when one was settled.
  @StringField(enumValues: supportedCurrencyCodes)
  String? get currency;

  /// The resolved household-local date, `YYYY-MM-DD` (default: today).
  @StringField(description: 'Resolved household-local date, YYYY-MM-DD.')
  String? get date;

  /// Account, person, category and who hints matched in the text.
  List<$ParseHint>? get hints;

  /// Learned rules that matched.
  List<$RuleHit>? get ruleHits;

  /// Complexity signals for the router (AI_PIPELINE 2).
  $ComplexitySignals? get signals;
}

/// One amount found by the parser.
@Schema(description: 'An amount found in the message.')
abstract class $ParsedAmount {
  /// Amount in minor units of [currency]; set when the currency is known.
  @IntegerField(description: 'Amount in minor units of currency.', minimum: 0)
  int? get amountMinor;

  /// The amount's currency, from a currency word or the account default.
  @StringField(enumValues: supportedCurrencyCodes)
  String? get currency;

  /// The exact major-unit value as a plain decimal string, for example
  /// `"25000"` or `"12.5"`, kept when the currency is not yet known.
  @StringField(description: 'Major-unit value as a plain decimal string.')
  String? get value;

  /// The matched text span.
  String? get span;

  /// Start offset of [span] in the normalised text.
  @IntegerField(minimum: 0)
  int? get start;

  /// End offset (exclusive) of [span] in the normalised text.
  @IntegerField(minimum: 0)
  int? get end;

  /// Whether the amount was inferred (for example dropped thousands) and
  /// should show the "Guessed" badge.
  bool? get guessed;
}

/// A hint matched against the household's names and aliases.
@Schema(description: 'An account, person, category or who hint.')
abstract class $ParseHint {
  /// What the hint points at.
  @StringField(enumValues: parseHintKindValues)
  String get kind;

  /// The matched text span.
  String? get span;

  /// The resolved id (account, person or category), when resolved.
  String? get id;

  /// The resolved value for `who` hints (`me`, `partner`, `joint`).
  @StringField(enumValues: whoValues)
  String? get who;

  /// Confidence of the match, 0 to 1.
  @DoubleField(minimum: 0, maximum: 1)
  double? get confidence;
}

/// A learned rule that matched (DATA_MODEL 2.12).
@Schema(description: 'A learned rule that matched the message.')
abstract class $RuleHit {
  /// The rule's id.
  String get ruleId;

  /// The field the rule sets.
  @StringField(enumValues: ruleFieldValues)
  String get field;

  /// The value the rule sets (an id, a `who` value or an intent).
  String get value;

  /// Confidence; rule hits are 0.99 (AI_PIPELINE 5).
  @DoubleField(minimum: 0, maximum: 1)
  double? get confidence;
}

/// The router's complexity signals (AI_PIPELINE 2).
@Schema(description: 'Complexity signals used by the router.')
abstract class $ComplexitySignals {
  /// Number of amounts found.
  @IntegerField(minimum: 0)
  int? get amountCount;

  /// A conjunction joins clauses that each hold an amount or a verb.
  bool? get hasConjunction;

  /// The message asks about data.
  bool? get isQuestion;

  /// The message is a command (delete, change, undo, set budget, new goal).
  bool? get isCommand;

  /// Money went to or came from a named person.
  bool? get hasPersonTransfer;

  /// Required fields still missing after rules.
  List<String>? get unresolved;

  /// The attachment type.
  @StringField(enumValues: attachmentValues)
  String? get attachment;
}
