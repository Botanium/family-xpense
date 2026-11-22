import 'package:schemantic/schemantic.dart';
import 'package:xpense_shared/money/currency.dart';
import 'package:xpense_shared/schema/wire_values.dart';
import 'package:xpense_shared/taxonomy/intents.dart';

part 'entry_draft.g.dart';

/// One proposed money entry, before the user saves it (AI_PIPELINE 8).
///
/// Produced by the parser, rules, the on-device model, the Decisions API or
/// the agent, and rendered by the `EntryList` card. Everything except [id]
/// and [intent] is nullable so partial drafts and reloaded session state
/// parse without throwing.
@Schema(description: 'A proposed money entry awaiting confirmation.')
abstract class $EntryDraft {
  /// Draft id, unique within the surface.
  @Field(description: 'Draft id, unique within the surface.')
  String get id;

  /// The money intent; never `question`, `command` or `other`.
  @StringField(enumValues: entryIntentWireValues)
  String get intent;

  /// Amount in minor units of [currency]; always positive.
  @IntegerField(
    description: 'Amount in minor units of currency (cents, whole dinars).',
    minimum: 1,
  )
  int? get amountMinor;

  /// ISO currency code; equals the account's currency.
  @StringField(enumValues: supportedCurrencyCodes)
  String? get currency;

  /// The account money leaves (or enters, for income-like intents).
  String? get accountId;

  /// The destination account of a transfer or savings move.
  String? get toAccountId;

  /// The category id (required for expense and income before saving).
  String? get categoryId;

  /// Whose entry this is.
  @StringField(enumValues: whoValues)
  String? get who;

  /// Household-local date, `YYYY-MM-DD`.
  @StringField(description: 'Household-local date, YYYY-MM-DD.')
  String? get occurredOn;

  /// Household-local time, `HH:mm`.
  @StringField(description: 'Household-local time, HH:mm.')
  String? get occurredTime;

  /// Merchant or short label.
  @StringField(maxLength: 80)
  String? get title;

  /// Free-text note.
  @StringField(maxLength: 500)
  String? get note;

  /// Counterparty name as spoken, for loans and repayments.
  String? get personName;

  /// Resolved counterparty id.
  String? get personId;

  /// The loan this entry belongs to.
  String? get loanId;

  /// The goal of a savings move.
  String? get goalId;

  /// The conversion into the household base currency.
  $FxQuote? get fx;

  /// Per-field confidence, 0 to 1.
  $DraftConfidence? get confidence;

  /// Field names shown with the "Guessed" badge.
  List<String>? get guessed;

  /// Required field names still empty.
  List<String>? get missing;

  /// A possible duplicate of a saved entry.
  $DuplicateHint? get duplicate;

  /// A guess that this entry repeats.
  $RecurringHint? get recurring;

  /// The step that produced this draft.
  @StringField(enumValues: draftOriginValues)
  String? get origin;
}

/// The FX conversion stored with an entry (`transactions.fx`, DATA_MODEL 1).
@Schema(description: 'Exchange rate used to compute the base amount.')
abstract class $FxQuote {
  /// Market-convention pair, for example `USD/IQD`.
  @StringField(description: 'Market-convention pair, for example USD/IQD.')
  String get pair;

  /// The rate as a decimal string, for example `"1520"`; never a float.
  @StringField(description: 'Rate as a decimal string, for example "1520".')
  String get pairRate;

  /// The household's label for the rate.
  @StringField(enumValues: fxSourceValues)
  String? get source;

  /// The household-local day the rate is for, `YYYY-MM-DD`.
  @StringField(description: 'Day of the rate, YYYY-MM-DD.')
  String? get asOf;

  /// The amount in the household base currency, rounded half-even once.
  @IntegerField(description: 'Amount in base-currency minor units.')
  int? get baseAmountMinor;
}

/// Confidence of a draft's classified fields, each 0 to 1.
@Schema(description: 'Per-field confidence, 0 to 1.')
abstract class $DraftConfidence {
  /// Confidence in the intent.
  @DoubleField(minimum: 0, maximum: 1)
  double? get intent;

  /// Confidence in the category.
  @DoubleField(minimum: 0, maximum: 1)
  double? get category;

  /// Confidence in the account.
  @DoubleField(minimum: 0, maximum: 1)
  double? get account;

  /// Confidence in who the entry belongs to.
  @DoubleField(minimum: 0, maximum: 1)
  double? get who;
}

/// A saved entry this draft may duplicate.
@Schema(description: 'A saved entry this draft may duplicate.')
abstract class $DuplicateHint {
  /// The saved transaction's id.
  String get txnId;

  /// Probability that the draft is the same event, 0 to 1.
  @DoubleField(minimum: 0, maximum: 1)
  double? get probability;
}

/// A guess that the entry repeats (`recurring.cadence`, DATA_MODEL 2.11).
@Schema(description: 'A guess that this entry repeats.')
abstract class $RecurringHint {
  /// Probability that the entry repeats, 0 to 1.
  @DoubleField(minimum: 0, maximum: 1)
  double? get probability;

  /// The repeat unit.
  @StringField(enumValues: cadenceUnitValues)
  String? get unit;

  /// Repeat every this many units.
  @IntegerField(minimum: 1)
  int? get interval;

  /// Day of the month, for monthly cadence.
  @IntegerField(minimum: 1, maximum: 31)
  int? get dayOfMonth;

  /// ISO weekday (1 is Monday), for weekly cadence.
  @IntegerField(minimum: 1, maximum: 7)
  int? get weekday;

  /// An existing recurring template this matches, if any.
  String? get recurringId;
}
