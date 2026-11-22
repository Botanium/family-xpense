import 'package:schemantic/schemantic.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/schema/parse_result.dart';

part 'decide.g.dart';

/// The phone's request to `POST /decide` (AI_PIPELINE 7):
/// `{text, lang, parsed, hints, ask, candidates?}`.
///
/// The server builds the question options from the household's own data,
/// so the phone sends only keys, never option lists.
@Schema(description: 'Request to the Decisions proxy.')
abstract class $DecideRequest {
  /// The message text.
  String get text;

  /// Language code of [text]; `en` only for now (D-36).
  String get lang;

  /// What the fast parser already settled.
  $DecideParsed? get parsed;

  /// Hints from the fast parser.
  List<$ParseHint>? get hints;

  /// The question keys to ask, from `decideQuestionKeys`.
  List<String> get ask;

  /// Ignored by the server since WP-33: it finds duplicate candidates itself
  /// among the saved entries the speaker can see. Kept for compatibility.
  List<$DuplicateCandidate>? get candidates;
}

/// The settled part of a message sent with a decide request.
@Schema(description: 'Amount, currency and date already parsed.')
abstract class $DecideParsed {
  /// Amount in minor units of [currency].
  @IntegerField(minimum: 0)
  int? get amountMinor;

  /// ISO currency code.
  @StringField(enumValues: supportedCurrencyCodes)
  String? get currency;

  /// Household-local date, `YYYY-MM-DD`.
  String? get date;
}

/// A recent entry that may be the same event as the message.
@Schema(description: 'A recent saved entry that may be a duplicate.')
abstract class $DuplicateCandidate {
  /// The saved transaction's id; also the option key.
  String get txnId;

  /// Amount in minor units of [currency].
  int? get amountMinor;

  /// ISO currency code.
  @StringField(enumValues: supportedCurrencyCodes)
  String? get currency;

  /// Household-local date, `YYYY-MM-DD`.
  String? get occurredOn;

  /// Merchant or short label.
  String? get title;
}

/// The proxy's answer (AI_PIPELINE 7). Each field answers the question key
/// of the same name; unasked questions are absent.
@Schema(description: 'Answers from the Decisions proxy.')
abstract class $DecideResponse {
  /// Answer to `intent`.
  $ChoiceAnswer? get intent;

  /// Answer to `category`.
  $ChoiceAnswer? get category;

  /// Answer to `account`: the account the money left from or arrived in.
  $ChoiceAnswer? get account;

  /// Answer to `to_account`: the destination account of a transfer or
  /// savings move (WP-S4).
  @Field(name: 'to_account')
  $ChoiceAnswer? get toAccount;

  /// Answer to `person`: the household's person a loan, repayment or gift
  /// is with (WP-S4).
  $ChoiceAnswer? get person;

  /// Answer to `who`.
  $ChoiceAnswer? get who;

  /// Answer to `multi_entry`; at 0.5 or above the phone re-routes to the
  /// agent.
  @Field(name: 'multi_entry')
  $YesNoAnswer? get multiEntry;

  /// Answer to `repayable`.
  $YesNoAnswer? get repayable;

  /// Answer to `needs_followup`.
  @Field(name: 'needs_followup')
  $YesNoAnswer? get needsFollowup;

  /// Answer to `is_recurring`.
  @Field(name: 'is_recurring')
  $YesNoAnswer? get isRecurring;

  /// Answer to `duplicate`: whether the message is one of the candidates.
  $YesNoAnswer? get duplicate;

  /// The transaction id of the nearest duplicate candidate, set whenever
  /// [duplicate] is. The slip's "Looks like one you already saved" links to
  /// it (`EntryDraft.duplicate.txnId`).
  @Field(name: 'duplicate_of')
  String? get duplicateOf;

  /// `false` when the answers came from the Flash-Lite fallback; the phone
  /// then caps confidences at `conf_on_device_cap`.
  bool? get calibrated;

  /// `true` when no classifier was available; the phone falls back to
  /// on-device classification or local pickers.
  bool? get unavailable;
}

/// The answer to a `choice` question.
@Schema(description: 'Answer to a choice question.')
abstract class $ChoiceAnswer {
  /// The most probable option key.
  String? get choice;

  /// Probability per option key. `num` so that a probability of exactly 0
  /// or 1 encoded as a JSON integer still reads.
  Map<String, num>? get probabilities;

  /// The classifier's confidence in [choice], 0 to 1.
  @DoubleField(minimum: 0, maximum: 1)
  double? get confidence;
}

/// The answer to a yes/no (`noul`) question.
@Schema(description: 'Answer to a yes/no question.')
abstract class $YesNoAnswer {
  /// Probability of yes, 0 to 1.
  @DoubleField(minimum: 0, maximum: 1)
  double? get probability;

  /// The classifier's confidence, 0 to 1.
  @DoubleField(minimum: 0, maximum: 1)
  double? get confidence;
}
