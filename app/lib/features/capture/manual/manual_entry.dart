// The Add manually form as plain data (DESIGN_SYSTEM screen 9, BACKLOG
// S2.2): what the member typed and picked, the check that turns it into an
// `EntryDraft` for the write path, and the mapping of the write path's
// typed failures back onto the form's fields. Pure Dart, tested without
// widgets.
import 'package:flutter/foundation.dart';
import 'package:xpense_app/core/ui/money_text.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The four tabs of the sheet's type bar.
enum ManualKind {
  /// Money spent.
  expense,

  /// Money received.
  income,

  /// Money moved between two of the household's accounts.
  transfer,

  /// Money lent, borrowed or paid back.
  loan;

  /// The tab for a draft's [intent], or null for one the form does not
  /// offer as a tab (an adjustment).
  static ManualKind? fromIntent(String intent) =>
      switch (CaptureIntent.tryParse(intent)) {
        CaptureIntent.expense => expense,
        CaptureIntent.income => income,
        CaptureIntent.transfer || CaptureIntent.savingsMove => transfer,
        CaptureIntent.loanGiven ||
        CaptureIntent.loanTaken ||
        CaptureIntent.repaymentReceived ||
        CaptureIntent.repaymentMade => loan,
        _ => null,
      };
}

/// Which way a loan event moves money, on the Loan tab.
enum LoanDirection {
  /// The member lent money (`loan_given`).
  lent('loan_given'),

  /// The member borrowed money (`loan_taken`).
  borrowed('loan_taken'),

  /// Someone paid the member back (`repayment_received`).
  paidBack('repayment_received'),

  /// The member paid someone back (`repayment_made`).
  repaid('repayment_made');

  new(this.intent);

  /// The draft intent.
  final String intent;

  /// Whether money comes into the account.
  bool get incoming => this == borrowed || this == paidBack;

  /// The direction of [intent], or null for another intent.
  static LoanDirection? fromIntent(String intent) =>
      values.where((d) => d.intent == intent).firstOrNull;
}

/// The fields the form shows errors next to.
enum ManualField {
  /// The amount.
  amount,

  /// The account (and with it the currency).
  account,

  /// A transfer's destination.
  toAccount,

  /// What arrives in a transfer's destination in another currency.
  toAmount,

  /// The category.
  category,

  /// Whose it is.
  who,

  /// The day and time.
  date,

  /// The counterparty of a loan event.
  person,

  /// The note.
  note,

  /// The rate typed for this entry.
  rate,
}

/// What is wrong with a field.
enum ManualIssue {
  /// It is empty.
  missing,

  /// It does not read: not a number, more decimals than the currency has.
  invalid,

  /// The amount is zero or too large.
  outOfRange,

  /// Longer than the field takes.
  tooLong,

  /// A transfer to the account it leaves.
  sameAccount,

  /// The household has no such account, category or person any more.
  unknown,

  /// An expense category on income, or the reverse.
  wrongKind,

  /// The currency differs from the account's or the loan's.
  currencyMismatch,

  /// "Partner" before the partner has joined.
  noPartner,

  /// The entry needs the USD/IQD rate and the household has none.
  rateNeeded,
}

/// The longest note (DATA_MODEL 2.5).
const int manualNoteMaxLength = 500;

/// The longest counterparty name: it becomes the title (DATA_MODEL 2.5).
const int manualPersonMaxLength = 80;

/// What the form holds. Immutable; the sheet replaces it on every edit.
@immutable
final class ManualEntryValues {
  /// Creates the values.
  const new({
    required this.kind,
    required this.occurredOn,
    this.loanDirection = LoanDirection.lent,
    this.amountText = '',
    this.accountId,
    this.toAccountId,
    this.toAmountText = '',
    this.categoryId,
    this.who,
    this.occurredTime,
    this.note = '',
    this.personName = '',
    this.rateText = '',
    this.rateAsked = false,
    this.otherIntent,
    this.savingsMove = false,
  });

  /// The values of a prefilled [draft]: "Change" on a slip, or an edit
  /// from entry detail. [today] fills a missing day.
  factory fromDraft(EntryDraft draft, {required String today}) {
    final kind = ManualKind.fromIntent(draft.intent);
    final currency = Currency.tryParse(draft.currency ?? '');
    final fx = draft.fx;
    return ManualEntryValues(
      kind: kind ?? ManualKind.expense,
      otherIntent: kind == null ? draft.intent : null,
      savingsMove: draft.intent == CaptureIntent.savingsMove.wire,
      loanDirection:
          LoanDirection.fromIntent(draft.intent) ?? LoanDirection.lent,
      amountText: switch ((draft.amountMinor, currency)) {
        (final int minor, final Currency c) => plainAmount(minor, c.exponent),
        _ => '',
      },
      accountId: draft.accountId,
      toAccountId: draft.toAccountId,
      categoryId: draft.categoryId,
      who: draft.who,
      occurredOn: draft.occurredOn ?? today,
      occurredTime: draft.occurredTime,
      note: draft.note ?? '',
      personName: draft.personName ?? '',
      // A rate the draft carries (a stored one, on an edit) is kept as it
      // is; the field shows only when the write path asks for one.
      rateText: fx == null ? '' : fx.pairRate,
    );
  }

  /// The tab.
  final ManualKind kind;

  /// An intent the tabs do not offer (an adjustment being edited); it is
  /// kept as it is and the type bar is hidden.
  final String? otherIntent;

  /// Whether the Transfer tab holds a savings move (into a goal's
  /// account), as a prefilled draft said. It stays one until the member
  /// picks another tab.
  final bool savingsMove;

  /// The Loan tab's direction.
  final LoanDirection loanDirection;

  /// The amount as typed, in the account's currency.
  final String amountText;

  /// The account money leaves (or enters).
  final String? accountId;

  /// A transfer's destination.
  final String? toAccountId;

  /// What arrives, as typed, when a transfer crosses currencies; empty
  /// converts with the rate.
  final String toAmountText;

  /// The category (expense and income).
  final String? categoryId;

  /// `me`, `partner` or `joint`; null lets the account decide.
  final String? who;

  /// Household-local day, `YYYY-MM-DD`.
  final String occurredOn;

  /// Household-local time, `HH:mm`, when known.
  final String? occurredTime;

  /// The note.
  final String note;

  /// The counterparty of a loan event.
  final String personName;

  /// The USD/IQD rate typed for this entry.
  final String rateText;

  /// Whether the write path asked for a rate, so the field shows.
  final bool rateAsked;

  /// The draft intent.
  String get intent =>
      otherIntent ??
      switch (kind) {
        ManualKind.expense => CaptureIntent.expense.wire,
        ManualKind.income => CaptureIntent.income.wire,
        ManualKind.transfer =>
          savingsMove
              ? CaptureIntent.savingsMove.wire
              : CaptureIntent.transfer.wire,
        ManualKind.loan => loanDirection.intent,
      };

  /// The category kind the chips offer, or null when the entry has none.
  CategoryKind? get categoryKind => switch (intent) {
    'expense' => CategoryKind.expense,
    'income' => CategoryKind.income,
    _ => null,
  };

  /// A copy with the given fields replaced. [who], [accountId],
  /// [toAccountId] and [categoryId] are cleared with the `clear…` flags.
  ManualEntryValues copyWith({
    ManualKind? kind,
    LoanDirection? loanDirection,
    String? amountText,
    String? accountId,
    String? toAccountId,
    String? toAmountText,
    String? categoryId,
    bool clearCategory = false,
    String? who,
    String? occurredOn,
    String? occurredTime,
    String? note,
    String? personName,
    String? rateText,
    bool? rateAsked,
  }) => ManualEntryValues(
    kind: kind ?? this.kind,
    otherIntent: otherIntent,
    // Another tab ends a savings move: coming back is a plain transfer.
    savingsMove: savingsMove && (kind == null || kind == this.kind),
    loanDirection: loanDirection ?? this.loanDirection,
    amountText: amountText ?? this.amountText,
    accountId: accountId ?? this.accountId,
    toAccountId: toAccountId ?? this.toAccountId,
    toAmountText: toAmountText ?? this.toAmountText,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    who: who ?? this.who,
    occurredOn: occurredOn ?? this.occurredOn,
    occurredTime: occurredTime ?? this.occurredTime,
    note: note ?? this.note,
    personName: personName ?? this.personName,
    rateText: rateText ?? this.rateText,
    rateAsked: rateAsked ?? this.rateAsked,
  );

  @override
  bool operator ==(Object other) =>
      other is ManualEntryValues &&
      other.kind == kind &&
      other.otherIntent == otherIntent &&
      other.savingsMove == savingsMove &&
      other.loanDirection == loanDirection &&
      other.amountText == amountText &&
      other.accountId == accountId &&
      other.toAccountId == toAccountId &&
      other.toAmountText == toAmountText &&
      other.categoryId == categoryId &&
      other.who == who &&
      other.occurredOn == occurredOn &&
      other.occurredTime == occurredTime &&
      other.note == note &&
      other.personName == personName &&
      other.rateText == rateText &&
      other.rateAsked == rateAsked;

  @override
  int get hashCode => Object.hash(
    kind,
    otherIntent,
    savingsMove,
    loanDirection,
    amountText,
    accountId,
    toAccountId,
    toAmountText,
    categoryId,
    who,
    occurredOn,
    occurredTime,
    note,
    personName,
    rateText,
    rateAsked,
  );

  /// [minor] as the form types it: digits and the currency's decimals,
  /// no grouping, such as `42.80` or `10000`.
  static String plainAmount(int minor, int exponent) {
    final figure = MoneyFormat.figure(minor, exponent: exponent);
    return '${figure.whole.replaceAll(',', '')}${figure.fraction}';
  }
}

/// The result of [checkManualEntry]: a draft to save, or the fields to
/// fix.
@immutable
final class ManualEntryCheck {
  /// Creates the result.
  const new({
    this.draft,
    this.extras = const EntryExtras(),
    this.errors = const {},
  });

  /// The draft, when every field reads.
  final EntryDraft? draft;

  /// What the draft cannot carry: a typed arriving amount.
  final EntryExtras extras;

  /// What is wrong, by field.
  final Map<ManualField, ManualIssue> errors;

  /// Whether the form can be saved.
  bool get ok => draft != null && errors.isEmpty;
}

/// Reads [values] into an [EntryDraft] with id [draftId].
///
/// [currencyOf] gives an account's currency (null for one the member
/// cannot see); [base] is the household's base currency, for the rate
/// field. [initial] is the prefilled draft, whose fields the form does not
/// show (title, person and loan ids, goal, origin, AI confidence) are kept,
/// so "Change" on a slip and an edit lose nothing.
///
/// [arrivesWasTyped] says Arrives opened with a typed arriving amount (an
/// edit): emptied, it asks the write path to convert again
/// ([EntryExtras.toAmountReset]) instead of keeping the stored amount.
///
/// The write path checks the draft again against the household cache;
/// this only catches what the form can know.
ManualEntryCheck checkManualEntry(
  ManualEntryValues values, {
  required String draftId,
  required Currency? Function(String accountId) currencyOf,
  required Currency base,
  EntryDraft? initial,
  bool arrivesWasTyped = false,
}) {
  final errors = <ManualField, ManualIssue>{};
  final currency = switch (values.accountId) {
    null => null,
    final id => currencyOf(id),
  };
  if (values.accountId == null) {
    errors[ManualField.account] = ManualIssue.missing;
  } else if (currency == null) {
    errors[ManualField.account] = ManualIssue.unknown;
  }

  int? amount;
  if (values.amountText.trim().isEmpty) {
    errors[ManualField.amount] = ManualIssue.missing;
  } else if (currency != null) {
    amount = MoneyFormat.parseMinor(
      values.amountText,
      exponent: currency.exponent,
    );
    if (amount == null) {
      errors[ManualField.amount] = ManualIssue.invalid;
    } else if (amount < 1 || amount > maxDraftAmountMinor) {
      errors[ManualField.amount] = ManualIssue.outOfRange;
    }
  }

  final intent = values.intent;
  final transfer =
      intent == CaptureIntent.transfer.wire ||
      intent == CaptureIntent.savingsMove.wire;
  final keepsGoal =
      intent == CaptureIntent.savingsMove.wire && initial?.goalId != null;
  int? toAmount;
  var toAmountReset = false;
  if (transfer && !keepsGoal) {
    final toId = values.toAccountId;
    final toCurrency = toId == null ? null : currencyOf(toId);
    if (toId == null) {
      errors[ManualField.toAccount] = ManualIssue.missing;
    } else if (toId == values.accountId) {
      errors[ManualField.toAccount] = ManualIssue.sameAccount;
    } else if (toCurrency == null) {
      errors[ManualField.toAccount] = ManualIssue.unknown;
    } else if (currency != null &&
        toCurrency != currency &&
        values.toAmountText.trim().isEmpty) {
      toAmountReset = arrivesWasTyped;
    } else if (currency != null &&
        toCurrency != currency &&
        values.toAmountText.trim().isNotEmpty) {
      toAmount = MoneyFormat.parseMinor(
        values.toAmountText,
        exponent: toCurrency.exponent,
      );
      if (toAmount == null) {
        errors[ManualField.toAmount] = ManualIssue.invalid;
      } else if (toAmount < 1 || toAmount > maxDraftAmountMinor) {
        errors[ManualField.toAmount] = ManualIssue.outOfRange;
      }
    }
  }

  // A category of the other kind (left from another tab) shows as none
  // chosen, so it counts as none.
  final categoryKind = values.categoryKind;
  final categoryDef = defaultCategories
      .where((c) => c.slug == values.categoryId)
      .firstOrNull;
  final categoryFits =
      values.categoryId != null &&
      (categoryDef == null || categoryDef.kind == categoryKind);
  if (categoryKind != null && !categoryFits) {
    errors[ManualField.category] = ManualIssue.missing;
  }

  final loan = ManualKind.fromIntent(intent) == ManualKind.loan;
  final person = values.personName.trim();
  if (loan && initial?.personId == null && person.isEmpty) {
    errors[ManualField.person] = ManualIssue.missing;
  } else if (person.length > manualPersonMaxLength) {
    errors[ManualField.person] = ManualIssue.tooLong;
  }

  final note = values.note.trim();
  if (note.length > manualNoteMaxLength) {
    errors[ManualField.note] = ManualIssue.tooLong;
  }

  var fx = initial?.fx;
  if (values.rateAsked) {
    final rate = FxRate.forPair(
      FxPair.usdIqd,
      values.rateText.replaceAll(',', '').trim(),
    ).valueOrNull;
    if (values.rateText.trim().isEmpty) {
      errors[ManualField.rate] = ManualIssue.rateNeeded;
    } else if (rate == null) {
      errors[ManualField.rate] = ManualIssue.invalid;
    } else {
      // Typed for this entry only (DATA_MODEL 1: `manual`).
      fx = FxQuote(
        pair: FxPair.usdIqd.code,
        pairRate: values.rateText.replaceAll(',', '').trim(),
        source: 'manual',
        asOf: values.occurredOn,
      );
    }
  } else if (initial?.fx case final named?
      when currency != null &&
          currency != base &&
          named.asOf != null &&
          named.asOf != values.occurredOn) {
    // A stored rate belongs to its day: moved to another day, the entry
    // takes that day's rate (the write path's rule for edits).
    fx = null;
  }

  // One entry touches at most two accounts and a loan, far under the
  // batch's limit (PR #35); checked so a future multi-entry form keeps it.
  final touched = {
    ?values.accountId,
    if (transfer) ?values.toAccountId,
    ?initial?.loanId,
  };
  if (touched.length > maxAccountsPerSave) {
    errors[ManualField.account] = ManualIssue.invalid;
  }

  if (errors.isNotEmpty) return ManualEntryCheck(errors: errors);

  // A loan event's title is its person's name unless the member gave it
  // another (the write path stores `title ?? personName`). A title that
  // was only that name is dropped, so it follows a new name; one of its
  // own stays (Codex review, PR #39).
  final initialTitle = initial?.title;
  final initialPerson = initial?.personName?.trim();
  final titleFromPerson =
      ManualKind.fromIntent(initial?.intent ?? '') == ManualKind.loan &&
      initialTitle != null &&
      initialPerson != null &&
      initialTitle.trim() == initialPerson;
  final draft = EntryDraft(
    id: draftId,
    intent: intent,
    amountMinor: amount,
    currency: currency!.code,
    accountId: values.accountId,
    toAccountId: transfer && !keepsGoal ? values.toAccountId : null,
    categoryId: values.categoryKind == null ? null : values.categoryId,
    who: switch (ManualKind.fromIntent(intent)) {
      ManualKind.expense || ManualKind.income => values.who,
      _ => values.who ?? initial?.who,
    },
    occurredOn: values.occurredOn,
    occurredTime: values.occurredTime,
    title: titleFromPerson ? null : initialTitle,
    note: note.isEmpty ? null : note,
    personName: loan && person.isNotEmpty ? person : null,
    personId: loan ? initial?.personId : null,
    loanId: loan ? initial?.loanId : null,
    goalId: keepsGoal ? initial?.goalId : null,
    fx: fx,
    confidence: initial?.confidence,
    guessed: initial?.guessed,
    origin: initial?.origin,
  );
  return ManualEntryCheck(
    draft: draft,
    extras: EntryExtras(toAmountMinor: toAmount, toAmountReset: toAmountReset),
  );
}

/// Where a typed failure from the write path shows: next to a field, or
/// (null field) as a toast.
@immutable
final class ManualFailure {
  /// Creates the placement.
  const new({this.field, this.issue, this.toast});

  /// The field, when the failure is about one.
  final ManualField? field;

  /// What is wrong with [field].
  final ManualIssue? issue;

  /// The failure, when it is shown as a toast.
  final TransactionsFailure? toast;
}

/// Places [failure] on the form.
ManualFailure placeFailure(TransactionsFailure failure) => switch (failure) {
  EntryRateNeeded() => const ManualFailure(
    field: ManualField.rate,
    issue: ManualIssue.rateNeeded,
  ),
  EntryInvalid(:final field, :final issue) => switch (_fieldOf(field)) {
    null => ManualFailure(toast: failure),
    final f => ManualFailure(field: f, issue: _issueOf(issue)),
  },
  TransactionsNotAllowed() ||
  TooManyEntries() ||
  TransactionNotFound() ||
  TransactionDeleted() ||
  TransactionNotDeleted() ||
  TransactionConflict() ||
  TransactionsUnknown() => ManualFailure(toast: failure),
};

ManualField? _fieldOf(String draftField) => switch (draftField) {
  'amountMinor' => ManualField.amount,
  'accountId' || 'currency' => ManualField.account,
  'toAccountId' => ManualField.toAccount,
  'toAmountMinor' => ManualField.toAmount,
  'categoryId' => ManualField.category,
  'who' => ManualField.who,
  'occurredOn' || 'occurredTime' => ManualField.date,
  'personName' || 'personId' || 'loanId' || 'title' => ManualField.person,
  'note' => ManualField.note,
  'fx' => ManualField.rate,
  _ => null,
};

ManualIssue _issueOf(EntryIssue issue) => switch (issue) {
  EntryIssue.missing => ManualIssue.missing,
  EntryIssue.malformed || EntryIssue.notMoney => ManualIssue.invalid,
  EntryIssue.unknownReference => ManualIssue.unknown,
  EntryIssue.amountOutOfRange => ManualIssue.outOfRange,
  EntryIssue.currencyMismatch => ManualIssue.currencyMismatch,
  EntryIssue.sameAccount => ManualIssue.sameAccount,
  EntryIssue.wrongCategoryKind => ManualIssue.wrongKind,
  EntryIssue.noPartner => ManualIssue.noPartner,
  EntryIssue.tooLong => ManualIssue.tooLong,
};

/// Household-local day of [time], `YYYY-MM-DD`.
String manualDay(DateTime time) {
  final t = time.isUtc ? time.toLocal() : time;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}';
}

/// Whose an entry is when the member has not said: the same rule as the
/// write path's (`who` absent), so the chip shown is what is saved. A
/// joint account's entries are joint; a personal account's belong to its
/// owner, from [viewerUid]'s side (`me` or `partner`).
String defaultWho({
  required bool joint,
  required String? ownerUid,
  required String? viewerUid,
}) {
  if (joint) return 'joint';
  return ownerUid == null || ownerUid == viewerUid ? 'me' : 'partner';
}
