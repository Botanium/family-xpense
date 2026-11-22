/// The intent taxonomy and the ledger types it writes (AI_PIPELINE 4).
library;

/// The type stored on a transaction (`transactions.type`, DATA_MODEL 2.5).
enum LedgerType {
  /// Money spent.
  expense('expense'),

  /// Money received and kept.
  income('income'),

  /// Between own or joint accounts (also savings moves, with a `goalId`).
  transfer('transfer'),

  /// Lent to someone, to be repaid.
  loanGiven('loan_given'),

  /// Borrowed.
  loanTaken('loan_taken'),

  /// Someone pays us back.
  repaymentReceived('repayment_received'),

  /// We pay a loan or debt.
  repaymentMade('repayment_made'),

  /// Balance correction or opening balance.
  adjustment('adjustment');

  new(this.wire);

  /// The stored string.
  final String wire;

  /// The ledger type for a stored [wire] value, or `null`.
  static LedgerType? tryParse(String wire) {
    for (final type in LedgerType.values) {
      if (type.wire == wire) return type;
    }
    return null;
  }
}

/// What a captured message means (AI_PIPELINE 4).
///
/// Named `CaptureIntent` so it does not clash with Flutter's `Intent`.
///
/// The first nine record money and map to a [LedgerType]; `question`,
/// `command` and `other` write nothing.
enum CaptureIntent {
  /// Money spent.
  expense('expense', LedgerType.expense),

  /// Money received and kept.
  income('income', LedgerType.income),

  /// Between own or joint accounts.
  transfer('transfer', LedgerType.transfer),

  /// Into or out of a goal's account; written as a transfer with `goalId`.
  savingsMove('savings_move', LedgerType.transfer),

  /// Lent to someone, to be repaid.
  loanGiven('loan_given', LedgerType.loanGiven),

  /// Borrowed.
  loanTaken('loan_taken', LedgerType.loanTaken),

  /// Someone pays us back.
  repaymentReceived('repayment_received', LedgerType.repaymentReceived),

  /// We pay a loan or debt.
  repaymentMade('repayment_made', LedgerType.repaymentMade),

  /// Balance correction, opening balance.
  adjustment('adjustment', LedgerType.adjustment),

  /// Asks about data.
  question('question', null),

  /// Edit, delete, undo, set budget, create goal, change setting.
  command('command', null),

  /// Greeting or unclear; the catch-all.
  other('other', null);

  new(this.wire, this.ledgerType);

  /// The wire value used in schemas, prompts and the Decisions API.
  final String wire;

  /// The ledger type written, or `null` when nothing is recorded.
  final LedgerType? ledgerType;

  /// Whether this intent records money (and so can be an `EntryDraft`).
  bool get recordsMoney => ledgerType != null;

  /// The intent for a [wire] value, or `null`.
  static CaptureIntent? tryParse(String wire) {
    for (final intent in CaptureIntent.values) {
      if (intent.wire == wire) return intent;
    }
    return null;
  }
}

/// Wire values of every [CaptureIntent], in taxonomy order.
///
/// Kept in step with the enum by a test.
const List<String> intentWireValues = [
  'expense',
  'income',
  'transfer',
  'savings_move',
  'loan_given',
  'loan_taken',
  'repayment_received',
  'repayment_made',
  'adjustment',
  'question',
  'command',
  'other',
];

/// Wire values of the intents that record money: the `EntryDraft.intent`
/// enum. Kept in step with [CaptureIntent.recordsMoney] by a test.
const List<String> entryIntentWireValues = [
  'expense',
  'income',
  'transfer',
  'savings_move',
  'loan_given',
  'loan_taken',
  'repayment_received',
  'repayment_made',
  'adjustment',
];
