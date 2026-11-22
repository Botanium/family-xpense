/// Input and output schemas of the agent tools (AI_PIPELINE 8).
///
/// The model sees these JSON Schemas as the tool signatures, so field
/// descriptions are written for the model and kept short. Money crosses the
/// boundary as integer minor units with a currency code; the only exception
/// is [$ProposedEntry.amount], which carries the amount as the user wrote it
/// so `prepareEntries` can check it against the message.
library;

import 'package:schemantic/schemantic.dart';
import 'package:xpense_shared/xpense_shared.dart';

part 'schemas.g.dart';

// ---------------------------------------------------------------------------
// prepareEntries
// ---------------------------------------------------------------------------

/// One money event the model found in the user's message.
@Schema(description: 'One money event found in the message.')
abstract class $ProposedEntry {
  /// The money intent. Nullable like every field here: a model that leaves
  /// one out must get drafts that ask, not a failed tool.
  @StringField(enumValues: entryIntentWireValues)
  String? get intent;

  /// The amount exactly as written, in major units.
  @StringField(
    description:
        'The amount exactly as the user wrote it, in major units, digits '
        'only, e.g. "3200", "12.50", "25000". Omit if the user gave none. '
        'Never compute or convert it.',
  )
  String? get amount;

  /// The currency the user named.
  @StringField(enumValues: supportedCurrencyCodes)
  String? get currency;

  /// The words of the message about this entry.
  @StringField(
    description:
        'The words of the message about this entry only, copied verbatim, '
        'e.g. "paid the generator 50".',
    maxLength: 300,
  )
  String? get text;

  /// Date words as written.
  @StringField(
    description: 'Date words as written, e.g. "yesterday", "on the 3rd".',
  )
  String? get dateWords;

  /// Account words as written.
  @StringField(description: 'Account words as written, e.g. "the joint card".')
  String? get accountHint;

  /// Destination account words for a transfer or savings move.
  @StringField(description: 'Destination account words, for transfers.')
  String? get toAccountHint;

  /// Category words or a category slug.
  @StringField(description: 'Category words or slug, e.g. "groceries".')
  String? get categoryHint;

  /// The other person, for loans, repayments and gifts.
  @StringField(description: 'The other person, as named.')
  String? get person;

  /// Whose money it is, when the message says so.
  @StringField(enumValues: whoValues)
  String? get who;

  /// A merchant or short label.
  @StringField(description: 'Merchant or short label, e.g. "Generator".')
  String? get title;
}

/// `prepareEntries` input.
@Schema(description: 'Every money event in the message, in order.')
abstract class $PrepareEntriesInput {
  /// The entries; the whole set replaces any earlier drafts of this turn.
  @Field(
    description:
        'All entries of the message. Calling again replaces the whole set.',
  )
  List<$ProposedEntry>? get entries;
}

/// `prepareEntries` output.
@Schema(description: 'Checked drafts to render unchanged in one EntryList.')
abstract class $PrepareEntriesOutput {
  /// The drafts, ready for `$/drafts`.
  List<$EntryDraft> get drafts;

  /// The first follow-up to ask, if any: `{draftId, field}`.
  $FollowUp? get ask;

  /// Short notes for the model, e.g. an amount not found in the message.
  List<String>? get notes;
}

/// The one follow-up question the agent may ask this turn.
@Schema(description: 'The single follow-up question to ask, if any.')
abstract class $FollowUp {
  /// The draft the question is about.
  String get draftId;

  /// The draft's index in `drafts`.
  int get index;

  /// The field to ask about.
  String get field;

  /// Up to three suggested options.
  List<$FollowUpOption>? get options;
}

/// A suggested answer to a follow-up.
@Schema(description: 'A suggested answer.')
abstract class $FollowUpOption {
  /// Button label.
  String get label;

  /// The value written to the draft field.
  String get value;

  /// A short hint under the label.
  String? get hint;
}

// ---------------------------------------------------------------------------
// queryLedger
// ---------------------------------------------------------------------------

/// `queryLedger` input.
@Schema(description: 'Filters, grouping and metric over saved entries.')
abstract class $LedgerQuery {
  /// First day, inclusive.
  @StringField(description: 'First day, YYYY-MM-DD. Default: month start.')
  String? get from;

  /// Last day, inclusive.
  @StringField(description: 'Last day, YYYY-MM-DD. Default: today.')
  String? get to;

  /// Category slugs or ids; a group includes its sub-categories.
  List<String>? get categories;

  /// Account ids.
  List<String>? get accountIds;

  /// Whose entries.
  @StringField(enumValues: ['me', 'partner', 'joint', 'all'])
  String? get who;

  /// Ledger types; default expense.
  List<String>? get types;

  /// Words to find in title or note.
  String? get text;

  /// How to group the rows.
  @StringField(
    enumValues: ['none', 'day', 'week', 'month', 'category', 'account', 'who'],
  )
  String? get groupBy;

  /// The metric per row.
  @StringField(enumValues: ['sum', 'count', 'avg'])
  String? get metric;

  /// Maximum rows, largest first (time groups stay in date order).
  @IntegerField(minimum: 1, maximum: 50)
  int? get limit;
}

/// `queryLedger` output. Every figure is computed here; the model copies
/// them and never does arithmetic.
@Schema(description: 'Rows and totals in the household base currency.')
abstract class $LedgerResult {
  /// Base currency of every figure.
  String get currency;

  /// `sum`, `count` or `avg`.
  String get metric;

  /// Days covered.
  String get from;

  /// Days covered.
  String get to;

  /// Sum (or average, for `avg`) over every matching entry, in base-currency
  /// minor units; null for `count`.
  int? get totalMinor;

  /// Number of matching entries.
  int get count;

  /// The grouped rows.
  List<$LedgerRow> get rows;

  /// Daily totals for MiniBars, oldest first (only for `groupBy: day`).
  List<int>? get daily;
}

/// One grouped row.
@Schema(description: 'One group.')
abstract class $LedgerRow {
  /// Group key: a date, category slug, account id or who.
  String get key;

  /// Display label.
  String get label;

  /// Sum (or average) for the group in base-currency minor units; null for
  /// `count`.
  int? get amountMinor;

  /// Entries in the group.
  int get count;

  /// Share of the total, 0 to 1 (sum only).
  double? get share;
}

// ---------------------------------------------------------------------------
// getBalances
// ---------------------------------------------------------------------------

/// `getBalances` input.
@Schema(description: 'Which accounts to include.')
abstract class $BalancesQuery {
  /// Which accounts.
  @StringField(enumValues: ['all', 'mine', 'partner', 'joint'])
  String? get scope;
}

/// `getBalances` output.
@Schema(description: 'Account balances and the household total.')
abstract class $BalancesResult {
  /// The household base currency.
  String get baseCurrency;

  /// The accounts.
  List<$AccountBalance> get accounts;

  /// Sum in base currency; null when a rate is missing.
  int? get totalBaseMinor;

  /// True when some household accounts are private to the partner.
  bool get partialView;
}

/// One account's balance.
@Schema(description: 'One account.')
abstract class $AccountBalance {
  /// The account id.
  String get accountId;

  /// Display name.
  String get name;

  /// Account currency.
  String get currency;

  /// Balance in minor units of [currency].
  int get balanceMinor;

  /// `personal` or `joint`.
  String get scope;
}

// ---------------------------------------------------------------------------
// getBudgets
// ---------------------------------------------------------------------------

/// `getBudgets` input.
@Schema(description: 'Budget month.')
abstract class $BudgetsQuery {
  /// The month.
  @StringField(description: 'YYYY-MM. Default: this month.')
  String? get month;
}

/// `getBudgets` output.
@Schema(description: 'Budgets with spent and remaining.')
abstract class $BudgetsResult {
  /// The month.
  String get month;

  /// Base currency of every figure.
  String get currency;

  /// The budgets.
  List<$BudgetStatus> get budgets;
}

/// One budget.
@Schema(description: 'One budget.')
abstract class $BudgetStatus {
  /// The budget id.
  String get budgetId;

  /// Category name or "Total".
  String get label;

  /// Monthly limit.
  int get limitMinor;

  /// Spent this month.
  int get spentMinor;

  /// Limit minus spent (negative when over).
  int get remainingMinor;
}

// ---------------------------------------------------------------------------
// findLoans
// ---------------------------------------------------------------------------

/// `findLoans` input.
@Schema(description: 'Loan filters.')
abstract class $LoansQuery {
  /// A person's name.
  String? get person;

  /// `open`, `closed` or `all`; default open.
  @StringField(enumValues: ['open', 'closed', 'all'])
  String? get status;
}

/// `findLoans` output.
@Schema(description: 'Loans and debts.')
abstract class $LoansResult {
  /// The loans.
  List<$LoanInfo> get loans;
}

/// One loan.
@Schema(description: 'One loan or debt.')
abstract class $LoanInfo {
  /// The loan id.
  String get loanId;

  /// `given` (they owe us) or `taken` (we owe them).
  String get direction;

  /// The other person.
  String get personName;

  /// Amount lent or borrowed.
  int get principalMinor;

  /// Still owed.
  int get outstandingMinor;

  /// Currency.
  String get currency;

  /// `open` or `closed`.
  String get status;

  /// Due date.
  String? get dueOn;
}

// ---------------------------------------------------------------------------
// getFxRate
// ---------------------------------------------------------------------------

/// `getFxRate` input.
@Schema(description: 'Rate lookup.')
abstract class $FxRateQuery {
  /// Pair in market convention.
  @StringField(description: 'Pair, default "USD/IQD".')
  String? get pair;

  /// The day.
  @StringField(description: 'YYYY-MM-DD, default today.')
  String? get date;
}

/// `getFxRate` output.
@Schema(description: 'The household rate for a day.')
abstract class $FxRateResult {
  /// The pair.
  String get pair;

  /// The rate as a decimal string, or null when none was entered.
  String? get rate;

  /// `official` or `market`.
  String? get source;

  /// The day the rate was entered for.
  String? get asOf;
}

// ---------------------------------------------------------------------------
// findEntries
// ---------------------------------------------------------------------------

/// `findEntries` input.
@Schema(description: 'Find saved entries.')
abstract class $FindEntriesQuery {
  /// Words in title or note.
  String? get text;

  /// First day.
  @StringField(description: 'YYYY-MM-DD. Default: 60 days ago.')
  String? get from;

  /// Last day.
  @StringField(description: 'YYYY-MM-DD. Default: today.')
  String? get to;

  /// Amount as written, major units.
  @StringField(description: 'Amount as written, e.g. "45.20".')
  String? get amount;
}

/// `findEntries` output, shaped for `TransactionList`.
@Schema(description: 'Matching entries, newest first, at most 10.')
abstract class $FoundEntries {
  /// The entries.
  List<$FoundEntry> get items;
}

/// One entry, in the `TransactionList` item shape.
@Schema(description: 'One saved entry.')
abstract class $FoundEntry {
  /// The transaction id.
  String get txnId;

  /// Title.
  String get title;

  /// Category and account.
  String get subtitle;

  /// Amount in minor units of [currency].
  int get amountMinor;

  /// Currency.
  String get currency;

  /// Ledger type.
  String get type;

  /// Date.
  String get occurredOn;
}
