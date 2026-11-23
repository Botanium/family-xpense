// The transaction write path (WP-20, BACKLOG S2.1) over the in-memory
// store: every ledger type of DATA_MODEL 3, FX (DATA_MODEL 1), validation,
// edits, deletes, undo, conflicts and offline replay. After every scenario
// the stored balances must equal what the reconcile job would recompute
// from the ledger with the shared effect table.
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/data/write/ledger_store.dart';
import 'package:xpense_app/data/write/ledger_transactions_repository.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';
import 'package:xpense_app/services/write_journal.dart';
import 'package:xpense_shared/xpense_shared.dart';

const me = 'u-me';
const partner = 'u-partner';
const List<String> both = [me, partner];
final DateTime now = DateTime(2026, 11, 23, 10, 30);

MemoryLedgerStore newStore({List<String> members = both, DateTime? at}) {
  final store = MemoryLedgerStore(
    scope: const LedgerScope(householdId: 'h1', uid: me),
    householdInfo: LedgerHousehold(
      baseCurrency: Currency.usd,
      memberIds: members,
    ),
    clock: Clock.fixed(at ?? now),
  );
  store.accounts.addAll({
    'joint-usd': const LedgerAccount(
      id: 'joint-usd',
      currency: Currency.usd,
      visibleTo: both,
      joint: true,
    ),
    'cash-iqd': const LedgerAccount(
      id: 'cash-iqd',
      currency: Currency.iqd,
      visibleTo: [me],
      ownerUid: me,
    ),
    'mine-usd': const LedgerAccount(
      id: 'mine-usd',
      currency: Currency.usd,
      visibleTo: [me],
      ownerUid: me,
    ),
    'shared-iqd': const LedgerAccount(
      id: 'shared-iqd',
      currency: Currency.iqd,
      visibleTo: both,
      ownerUid: partner,
    ),
    'partner-private': const LedgerAccount(
      id: 'partner-private',
      currency: Currency.usd,
      visibleTo: [partner],
      ownerUid: partner,
    ),
    'savings': const LedgerAccount(
      id: 'savings',
      currency: Currency.usd,
      visibleTo: both,
      joint: true,
    ),
  });
  store.categories.addAll({
    'groceries': const LedgerCategory(id: 'groceries', kind: 'expense'),
    'salary': const LedgerCategory(id: 'salary', kind: 'income'),
  });
  store.loans.addAll({
    'loan-usd': const LedgerLoan(id: 'loan-usd', currency: Currency.usd),
    'loan-iqd': const LedgerLoan(id: 'loan-iqd', currency: Currency.iqd),
  });
  store.people.add('alex');
  store.goals['trip'] = 'savings';
  store.rates['2026-11-20'] = DayRate(
    day: '2026-11-20',
    rate: FxRate.forPair(FxPair.usdIqd, '1705').valueOrNull!,
    kind: 'market',
  );
  return store;
}

EntryDraft draft({
  String id = 'd1',
  String intent = 'expense',
  int? amount = 1250,
  String? currency,
  String? account = 'joint-usd',
  String? to,
  String? category,
  String? who,
  String? on,
  String? time,
  String? title,
  String? note,
  String? person,
  String? loan,
  String? goal,
  FxQuote? fx,
  String? origin,
}) => EntryDraft(
  id: id,
  intent: intent,
  amountMinor: amount,
  currency: currency,
  accountId: account,
  toAccountId: to,
  categoryId: category ?? (intent == 'expense' ? 'groceries' : null),
  who: who,
  occurredOn: on ?? '2026-11-23',
  occurredTime: time,
  title: title,
  note: note,
  personId: person,
  loanId: loan,
  goalId: goal,
  fx: fx,
  origin: origin,
);

/// The reconcile check: stored aggregates equal the ledger's sum.
void expectReconciled(MemoryLedgerStore store) {
  final totals = ledgerTotals([
    for (final fields in store.serverTransactions.values)
      ?LedgerLine.fromFields(fields),
  ]);
  Map<String, int> nonZero(Map<String, int> m) => {
    for (final e in m.entries)
      if (e.value != 0) e.key: e.value,
  };
  expect(nonZero(store.serverBalances), totals.accounts, reason: 'balances');
  expect(nonZero(store.outstanding), totals.loans, reason: 'loan outstanding');
}

Future<String> saveOne(
  LedgerTransactionsRepository repo,
  EntryDraft d, {
  EntryExtras? extras,
}) async {
  final result = await repo.saveEntries([d], extras: {d.id: ?extras});
  expect(result.isOk, true, reason: '$result');
  return result.valueOrNull!.txnIds.single;
}

void main() {
  late MemoryLedgerStore store;
  late LedgerTransactionsRepository repo;

  setUp(() {
    store = newStore();
    repo = LedgerTransactionsRepository(store);
  });

  tearDown(() => expectReconciled(store));

  group('saveEntries writes every ledger type (DATA_MODEL 3)', () {
    test('expense: money leaves the account', () async {
      final id = await saveOne(repo, draft(title: 'Lulu'));
      final doc = store.transactions[id]!;
      expect(doc['type'], 'expense');
      expect(doc['amountMinor'], 1250);
      expect(doc['currency'], 'USD');
      expect(doc['baseAmountMinor'], 1250);
      expect(doc['fx'], isNull);
      expect(doc['categoryId'], 'groceries');
      expect(doc['title'], 'Lulu');
      expect(store.balances['joint-usd'], -1250);
    });

    test('income: money arrives', () async {
      await saveOne(
        repo,
        draft(intent: 'income', category: 'salary', amount: 300000),
      );
      expect(store.balances['joint-usd'], 300000);
    });

    test('transfer in one currency moves the amount', () async {
      final id = await saveOne(
        repo,
        draft(intent: 'transfer', account: 'mine-usd', to: 'joint-usd'),
      );
      expect(store.balances, {'mine-usd': -1250, 'joint-usd': 1250});
      expect(store.transactions[id]!['toAmountMinor'], isNull);
    });

    test('savings move goes to the goal account', () async {
      final id = await saveOne(
        repo,
        draft(intent: 'savings_move', goal: 'trip'),
      );
      final doc = store.transactions[id]!;
      expect(doc['type'], 'transfer');
      expect(doc['toAccountId'], 'savings');
      expect(doc['goalId'], 'trip');
      expect(store.balances, {'joint-usd': -1250, 'savings': 1250});
    });

    test('loan_given lowers the account and raises the loan', () async {
      await saveOne(
        repo,
        draft(intent: 'loan_given', person: 'alex', loan: 'loan-usd'),
      );
      expect(store.balances['joint-usd'], -1250);
      expect(store.outstanding['loan-usd'], 1250);
    });

    test('loan_taken raises both', () async {
      await saveOne(
        repo,
        draft(intent: 'loan_taken', person: 'alex', loan: 'loan-usd'),
      );
      expect(store.balances['joint-usd'], 1250);
      expect(store.outstanding['loan-usd'], 1250);
    });

    test('repayment_received raises the account, lowers the loan', () async {
      await saveOne(
        repo,
        draft(intent: 'repayment_received', person: 'alex', loan: 'loan-usd'),
      );
      expect(store.balances['joint-usd'], 1250);
      expect(store.outstanding['loan-usd'], -1250);
    });

    test('repayment_made lowers both', () async {
      await saveOne(
        repo,
        draft(intent: 'repayment_made', person: 'alex', loan: 'loan-usd'),
      );
      expect(store.balances['joint-usd'], -1250);
      expect(store.outstanding['loan-usd'], -1250);
    });

    test('a loan event without a loan id moves no loan', () async {
      await saveOne(repo, draft(intent: 'loan_given', person: 'alex'));
      expect(store.outstanding, isEmpty);
    });

    test('adjustment takes its sign from the extras', () async {
      final up = await saveOne(repo, draft(intent: 'adjustment'));
      final down = await saveOne(
        repo,
        draft(intent: 'adjustment', account: 'mine-usd', amount: 900),
        extras: const EntryExtras(adjustmentSign: -1),
      );
      expect(store.transactions[up]!['adjustmentSign'], 1);
      expect(store.transactions[down]!['adjustmentSign'], -1);
      expect(store.balances, {'joint-usd': 1250, 'mine-usd': -900});
    });

    test('adjustmentSign is stored only on adjustments', () async {
      final id = await saveOne(
        repo,
        draft(),
        extras: const EntryExtras(adjustmentSign: -1),
      );
      expect(store.transactions[id]!['adjustmentSign'], isNull);
      expect(store.balances['joint-usd'], -1250);
    });
  });

  group('stored shape (DATA_MODEL 2.5, PR #33 requirements)', () {
    test('a live entry stores deletedAt: null, rev 0 and stamps', () async {
      final id = await saveOne(repo, draft());
      final doc = store.transactions[id]!;
      expect(doc.containsKey('deletedAt'), true);
      expect(doc['deletedAt'], isNull);
      expect(doc['rev'], 0);
      expect(doc['createdBy'], me);
      expect(doc['updatedBy'], me);
      expect(doc['createdAt'], isA<DateTime>());
      expect(doc['schemaVersion'], 1);
      expect(doc['occurredOn'], '2026-11-23');
      expect(doc['source'], 'manual');
    });

    test('visibleTo follows the accounts, never server-only fields', () async {
      final private = await saveOne(
        repo,
        draft(account: 'mine-usd', who: 'me'),
      );
      final transfer = await saveOne(
        repo,
        draft(intent: 'transfer', account: 'mine-usd', to: 'joint-usd'),
      );
      expect(store.transactions[private]!['visibleTo'], [me]);
      expect(store.transactions[transfer]!['visibleTo'], both);
      for (final doc in store.transactions.values) {
        expect(doc.keys, isNot(contains('visibilityAppliedTo')));
        expect(doc.keys, isNot(contains('visibilitySync')));
      }
    });

    test('ids are UUID v7 and the group shares one groupId', () async {
      final saved = await repo.saveEntries([
        draft(),
        draft(id: 'd2', amount: 50),
      ]);
      final value = saved.valueOrNull!;
      expect(value.txnIds, hasLength(2));
      expect(value.ack, WriteAck.synced);
      for (final id in value.txnIds) {
        expect(id, matches(RegExp('^[0-9a-f]{8}-[0-9a-f]{4}-7')));
        expect(store.transactions[id]!['groupId'], value.groupId);
      }
      expect(store.balances['joint-usd'], -1300);
      expect(store.committedBatches, 1);
    });

    test('who resolves to uids and scope', () async {
      final mine = await saveOne(repo, draft(who: 'me'));
      final theirs = await saveOne(repo, draft(who: 'partner'));
      final joint = await saveOne(repo, draft(who: 'joint'));
      final unsaid = await saveOne(repo, draft(account: 'shared-iqd'));
      expect(store.transactions[mine]!['whoUid'], me);
      expect(store.transactions[theirs]!['whoUid'], partner);
      expect(store.transactions[joint]!['whoScope'], 'joint');
      expect(store.transactions[joint]!['whoUid'], isNull);
      expect(store.transactions[unsaid]!['whoUid'], partner);
    });

    test('agent drafts record their path and default to chat', () async {
      final id = await saveOne(repo, draft(origin: 'agent'));
      final doc = store.transactions[id]!;
      expect(doc['source'], 'chat');
      expect((doc['ai']! as Map)['path'], 'agent');
    });

    test('the day and time give occurredAt', () async {
      final today = await saveOne(repo, draft());
      final past = await saveOne(repo, draft(on: '2026-11-01'));
      final timed = await saveOne(repo, draft(on: '2026-11-02', time: '08:15'));
      expect(store.transactions[today]!['occurredAt'], now.toUtc());
      expect(
        store.transactions[past]!['occurredAt'],
        DateTime(2026, 11, 1, 12).toUtc(),
      );
      expect(
        store.transactions[timed]!['occurredAt'],
        DateTime(2026, 11, 2, 8, 15).toUtc(),
      );
    });
  });

  group('FX (DATA_MODEL 1, D-16)', () {
    test('a non-base entry stores the day rate labelled market', () async {
      // 25,000 IQD at 1,705 = 14.66 USD (14.662… rounded half-even).
      final id = await saveOne(
        repo,
        draft(account: 'cash-iqd', amount: 25000, currency: 'IQD'),
      );
      final doc = store.transactions[id]!;
      expect(doc['currency'], 'IQD');
      expect(doc['baseAmountMinor'], 1466);
      expect(doc['fx'], {
        'pair': 'USD/IQD',
        'pairRate': '1705',
        'source': 'market',
        'asOf': '2026-11-20',
      });
      expect(store.balances['cash-iqd'], -25000);
    });

    test('the household label is used when it is official', () async {
      store.householdInfo = const LedgerHousehold(
        baseCurrency: Currency.usd,
        memberIds: both,
        rateKind: 'official',
      );
      final id = await saveOne(repo, draft(account: 'cash-iqd', amount: 1520));
      expect((store.transactions[id]!['fx']! as Map)['source'], 'official');
    });

    test('a rate named by the draft is used as manual', () async {
      final id = await saveOne(
        repo,
        draft(
          account: 'cash-iqd',
          amount: 152000,
          fx: FxQuote(pair: 'USD/IQD', pairRate: '1520', baseAmountMinor: 1),
        ),
      );
      final doc = store.transactions[id]!;
      expect(doc['baseAmountMinor'], 10000, reason: 'never the draft value');
      expect(doc['fx'], {
        'pair': 'USD/IQD',
        'pairRate': '1520',
        'source': 'manual',
        'asOf': '2026-11-23',
      });
    });

    test('no rate for the day or earlier asks for one', () async {
      final result = await repo.saveEntries([
        draft(account: 'cash-iqd', amount: 1000, on: '2026-11-19'),
      ]);
      expect(
        result.failureOrNull,
        const EntryRateNeeded(draftId: 'd1', from: 'IQD', to: 'USD'),
      );
      expect(store.transactions, isEmpty);
    });

    test('a malformed named rate is refused', () async {
      final result = await repo.saveEntries([
        draft(
          account: 'cash-iqd',
          amount: 1000,
          fx: FxQuote(pair: 'USD/IQD', pairRate: '1,520'),
        ),
      ]);
      expect(
        result.failureOrNull,
        const EntryInvalid(
          draftId: 'd1',
          field: 'fx',
          issue: EntryIssue.malformed,
        ),
      );
    });

    test('an IQD base household converts USD the other way', () async {
      store.householdInfo = const LedgerHousehold(
        baseCurrency: Currency.iqd,
        memberIds: both,
      );
      final id = await saveOne(repo, draft(amount: 1000)); // 10.00 USD
      expect(store.transactions[id]!['baseAmountMinor'], 17050);
      expect(store.transactions[id]!['fx'], isNotNull);
    });
  });

  group('cross-currency transfers', () {
    test('USD to IQD converts the arriving amount with the rate', () async {
      final id = await saveOne(
        repo,
        draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
      );
      final doc = store.transactions[id]!;
      // 12.50 USD × 1705 = 21,312.5 → 21,312 (half-even).
      expect(doc['toAmountMinor'], 21312);
      expect(doc['baseAmountMinor'], 1250);
      expect((doc['fx']! as Map)['pairRate'], '1705');
      expect(store.balances, {'mine-usd': -1250, 'cash-iqd': 21312});
    });

    test('a typed arriving amount needs no rate', () async {
      store.rates.clear();
      final id = await saveOne(
        repo,
        draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
        extras: const EntryExtras(toAmountMinor: 21000),
      );
      final doc = store.transactions[id]!;
      expect(doc['toAmountMinor'], 21000);
      expect(doc['fx'], isNull);
      expect(store.balances, {'mine-usd': -1250, 'cash-iqd': 21000});
    });

    test('IQD to USD fixes the base amount from the IQD side', () async {
      final id = await saveOne(
        repo,
        draft(
          intent: 'transfer',
          account: 'cash-iqd',
          to: 'mine-usd',
          amount: 170500,
        ),
      );
      final doc = store.transactions[id]!;
      expect(doc['baseAmountMinor'], 10000);
      expect(doc['toAmountMinor'], 10000);
      expect(store.balances, {'cash-iqd': -170500, 'mine-usd': 10000});
    });

    test('without a rate or typed amount it asks for the rate', () async {
      store.rates.clear();
      final result = await repo.saveEntries([
        draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
      ]);
      expect(
        result.failureOrNull,
        const EntryRateNeeded(draftId: 'd1', from: 'USD', to: 'IQD'),
      );
    });
  });

  group('validation against the household cache', () {
    Future<TransactionsFailure?> failureOf(
      List<EntryDraft> drafts, {
      Map<String, EntryExtras> extras = const {},
    }) async {
      final result = await repo.saveEntries(drafts, extras: extras);
      expect(store.transactions, isEmpty, reason: 'nothing is written');
      return result.failureOrNull;
    }

    EntryInvalid issue(String field, EntryIssue issue) =>
        EntryInvalid(draftId: 'd1', field: field, issue: issue);

    test('one bad draft stops the whole group', () async {
      expect(
        await failureOf([draft(id: 'ok'), draft(account: 'nope')]),
        issue('accountId', EntryIssue.unknownReference),
      );
    });

    test('unknown or invisible references', () async {
      expect(
        await failureOf([draft(account: 'partner-private')]),
        issue('accountId', EntryIssue.unknownReference),
      );
      expect(
        await failureOf([draft(category: 'nope')]),
        issue('categoryId', EntryIssue.unknownReference),
      );
      expect(
        await failureOf([draft(intent: 'loan_given', person: 'nobody')]),
        issue('personId', EntryIssue.unknownReference),
      );
      expect(
        await failureOf([
          draft(intent: 'loan_given', person: 'alex', loan: 'x'),
        ]),
        issue('loanId', EntryIssue.unknownReference),
      );
      expect(
        await failureOf([draft(intent: 'savings_move', goal: 'x')]),
        issue('goalId', EntryIssue.unknownReference),
      );
      expect(
        await failureOf([draft(intent: 'transfer', to: 'partner-private')]),
        issue('toAccountId', EntryIssue.unknownReference),
      );
    });

    test('missing required fields', () async {
      expect(
        await failureOf([draft(amount: null)]),
        issue('amountMinor', EntryIssue.missing),
      );
      expect(
        await failureOf([draft(account: null)]),
        issue('accountId', EntryIssue.missing),
      );
      expect(
        await failureOf([draft(intent: 'income')]),
        issue('categoryId', EntryIssue.missing),
      );
      expect(
        await failureOf([draft(intent: 'transfer')]),
        issue('toAccountId', EntryIssue.missing),
      );
      expect(
        await failureOf([draft(intent: 'loan_given')]),
        issue('personName', EntryIssue.missing),
      );
    });

    test('a field the producer left unanswered stops the save', () async {
      final unanswered = EntryDraft.fromJson({
        ...draft().toJson(),
        'missing': ['intent'],
      });
      expect(
        await failureOf([unanswered]),
        issue('intent', EntryIssue.missing),
      );
    });

    test('money rules', () async {
      expect(
        await failureOf([draft(currency: 'IQD')]),
        issue('currency', EntryIssue.currencyMismatch),
      );
      expect(
        await failureOf([draft(amount: 0)]),
        issue('amountMinor', EntryIssue.amountOutOfRange),
      );
      expect(
        await failureOf([
          draft(intent: 'loan_given', person: 'alex', loan: 'loan-iqd'),
        ]),
        issue('loanId', EntryIssue.currencyMismatch),
      );
      expect(
        await failureOf([
          draft(intent: 'transfer', account: 'mine-usd', to: 'mine-usd'),
        ]),
        issue('toAccountId', EntryIssue.sameAccount),
      );
      expect(
        await failureOf([draft(intent: 'income', category: 'groceries')]),
        issue('categoryId', EntryIssue.wrongCategoryKind),
      );
    });

    test('intents that record no money', () async {
      for (final intent in ['question', 'command', 'other']) {
        expect(
          await failureOf([draft(intent: intent)]),
          issue('intent', EntryIssue.notMoney),
        );
      }
    });

    test('text limits, dates and wrong types', () async {
      expect(
        await failureOf([draft(note: 'x' * 501)]),
        issue('note', EntryIssue.tooLong),
      );
      expect(
        await failureOf([draft(on: '2026-02-30')]),
        issue('occurredOn', EntryIssue.malformed),
      );
      expect(
        await failureOf([draft(time: '25:00')]),
        issue('occurredTime', EntryIssue.malformed),
      );
      final wrongType = EntryDraft.fromJson({
        ...draft().toJson(),
        'amountMinor': '12.50',
      });
      expect(
        await failureOf([wrongType]),
        issue('amountMinor', EntryIssue.malformed),
      );
    });

    test('a save touching more than 15 accounts is refused '
        '(Codex, PR #35)', () async {
      for (var i = 0; i < 16; i++) {
        store.accounts['x$i'] = LedgerAccount(
          id: 'x$i',
          currency: Currency.usd,
          visibleTo: both,
          joint: true,
        );
      }
      expect(
        await failureOf([
          for (var i = 0; i < 16; i++) draft(id: 'd$i', account: 'x$i'),
        ]),
        const TooManyEntries(),
      );
      // 15 fit one batch's rule reads.
      final saved = await repo.saveEntries([
        for (var i = 0; i < 15; i++) draft(id: 'd$i', account: 'x$i'),
      ]);
      expect(saved.valueOrNull?.txnIds, hasLength(15));
    });

    test('who: partner before the partner joins', () async {
      store = newStore(members: [me]);
      repo = LedgerTransactionsRepository(store);
      expect(
        await failureOf([draft(who: 'partner')]),
        issue('who', EntryIssue.noPartner),
      );
    });

    test('group size and household', () async {
      expect(await failureOf([]), const TooManyEntries());
      expect(
        await failureOf([
          for (var i = 0; i <= maxEntriesPerSave; i++) draft(id: 'd$i'),
        ]),
        const TooManyEntries(),
      );
      store.scope = null;
      expect(await failureOf([draft()]), const TransactionsNotAllowed());
    });
  });

  group('editEntry writes a revision and applies the difference', () {
    test('an amount change moves the balance by the delta', () async {
      final id = await saveOne(repo, draft(title: 'Lulu'));
      final result = await repo.editEntry(id, draft(amount: 2000));
      expect(result.valueOrNull, WriteAck.synced);
      final doc = store.transactions[id]!;
      expect(doc['amountMinor'], 2000);
      expect(doc['baseAmountMinor'], 2000);
      expect(doc['rev'], 1);
      expect(doc['title'], '', reason: 'the draft is the whole content');
      expect(store.balances['joint-usd'], -2000);
      final revision = store.revisions[id]!.single;
      expect(revision['rev'], 1);
      expect(revision['reason'], 'edit');
      expect(revision['changedBy'], me);
      expect(revision['before'], {
        'amountMinor': 1250,
        'baseAmountMinor': 1250,
        'title': 'Lulu',
      });
    });

    test('moving to another account and type', () async {
      final id = await saveOne(repo, draft());
      await repo.editEntry(
        id,
        draft(intent: 'transfer', account: 'mine-usd', to: 'savings'),
      );
      expect(store.balances, {
        'joint-usd': 0,
        'mine-usd': -1250,
        'savings': 1250,
      });
      expect(store.transactions[id]!['visibleTo'], both);
      expect(store.transactions[id]!['categoryId'], isNull);
    });

    test('a loan event edit moves the loan by the difference', () async {
      final id = await saveOne(
        repo,
        draft(intent: 'loan_given', person: 'alex', loan: 'loan-usd'),
      );
      await repo.editEntry(
        id,
        draft(
          intent: 'loan_given',
          person: 'alex',
          loan: 'loan-usd',
          amount: 5000,
        ),
      );
      expect(store.outstanding['loan-usd'], 5000);
    });

    test('nothing changed writes nothing', () async {
      final id = await saveOne(repo, draft());
      final batches = store.committedBatches;
      final result = await repo.editEntry(id, draft());
      expect(result.valueOrNull, WriteAck.synced);
      expect(store.committedBatches, batches);
      expect(store.revisions[id], isNull);
    });

    test('keeps its stored rate while the day stays', () async {
      final id = await saveOne(repo, draft(account: 'cash-iqd', amount: 17050));
      store.rates['2026-11-23'] = DayRate(
        day: '2026-11-23',
        rate: FxRate.forPair(FxPair.usdIqd, '1500').valueOrNull!,
      );
      await repo.editEntry(id, draft(account: 'cash-iqd', amount: 34100));
      final doc = store.transactions[id]!;
      expect((doc['fx']! as Map)['pairRate'], '1705');
      expect(doc['baseAmountMinor'], 2000);
    });

    test("a new day takes that day's rate", () async {
      final id = await saveOne(repo, draft(account: 'cash-iqd', amount: 15000));
      store.rates['2026-11-22'] = DayRate(
        day: '2026-11-22',
        rate: FxRate.forPair(FxPair.usdIqd, '1500').valueOrNull!,
      );
      await repo.editEntry(
        id,
        draft(account: 'cash-iqd', amount: 15000, on: '2026-11-22'),
      );
      final doc = store.transactions[id]!;
      expect((doc['fx']! as Map)['pairRate'], '1500');
      expect(doc['baseAmountMinor'], 1000);
    });

    test("keeps an adjustment's sign and a typed arriving amount", () async {
      final adj = await saveOne(
        repo,
        draft(intent: 'adjustment'),
        extras: const EntryExtras(adjustmentSign: -1),
      );
      await repo.editEntry(adj, draft(intent: 'adjustment', note: 'card'));
      expect(store.transactions[adj]!['adjustmentSign'], -1);

      final transfer = await saveOne(
        repo,
        draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
        extras: const EntryExtras(toAmountMinor: 20000),
      );
      await repo.editEntry(
        transfer,
        draft(
          intent: 'transfer',
          account: 'mine-usd',
          to: 'cash-iqd',
          note: 'rent',
        ),
      );
      expect(store.transactions[transfer]!['toAmountMinor'], 20000);
      expect(store.balances['cash-iqd'], 20000);
    });

    test('keeps source, group and creator', () async {
      final id = await saveOne(repo, draft(origin: 'agent'));
      final group = store.transactions[id]!['groupId'];
      await repo.editEntry(id, draft(amount: 99));
      final doc = store.transactions[id]!;
      expect(doc['source'], 'chat');
      expect(doc['groupId'], group);
      expect((doc['ai']! as Map)['path'], 'agent');
      expect(doc['createdBy'], me);
    });

    test('an invalid edit writes nothing', () async {
      final id = await saveOne(repo, draft());
      final result = await repo.editEntry(id, draft(account: 'nope'));
      expect(result.failureOrNull, isA<EntryInvalid>());
      expect(store.transactions[id]!['rev'], 0);
    });

    test("a note-only edit keeps a transfer's quote (Codex, PR #35)", () async {
      final id = await saveOne(
        repo,
        draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
      );
      final quote = store.transactions[id]!['fx'];
      expect(quote, isNotNull);
      await repo.editEntry(
        id,
        draft(
          intent: 'transfer',
          account: 'mine-usd',
          to: 'cash-iqd',
          note: 'rent',
        ),
      );
      final doc = store.transactions[id]!;
      expect(doc['note'], 'rent');
      expect(doc['fx'], quote);
      expect(doc['toAmountMinor'], 21312);
      expect(store.revisions[id]!.single['before'], {'note': null});
    });

    test('a new quote on a transfer edit converts again', () async {
      final id = await saveOne(
        repo,
        draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
      );
      await repo.editEntry(
        id,
        draft(
          intent: 'transfer',
          account: 'mine-usd',
          to: 'cash-iqd',
          fx: FxQuote(pair: 'USD/IQD', pairRate: '1500'),
        ),
      );
      final doc = store.transactions[id]!;
      // 12.50 USD × 1500.
      expect(doc['toAmountMinor'], 18750);
      expect((doc['fx']! as Map)['pairRate'], '1500');
      expect((doc['fx']! as Map)['source'], 'manual');
      expect(store.balances['cash-iqd'], 18750);
    });

    test('an unchanged prefilled time keeps the stored instant '
        '(Codex, PR #35)', () async {
      final at = DateTime(2026, 11, 23, 10, 30, 42, 123);
      store = newStore(at: at);
      repo = LedgerTransactionsRepository(store);
      final id = await saveOne(repo, draft(title: 'Lulu'));
      expect(store.transactions[id]!['occurredAt'], at.toUtc());
      final prefilled = draftFromTransaction(
        (await store.transaction(id))!,
        viewerUid: me,
      );
      expect(prefilled.occurredTime, '10:30');
      final batches = store.committedBatches;
      expect((await repo.editEntry(id, prefilled)).isOk, true);
      expect(store.committedBatches, batches, reason: 'nothing changed');
      await repo.editEntry(
        id,
        EntryDraft.fromJson({...prefilled.toJson(), 'note': 'card'}),
      );
      expect(store.transactions[id]!['occurredAt'], at.toUtc());
      expect(store.revisions[id]!.single['before'], {'note': null});
      // A changed minute does move it.
      await repo.editEntry(
        id,
        EntryDraft.fromJson({...prefilled.toJson(), 'occurredTime': '10:31'}),
      );
      expect(
        store.transactions[id]!['occurredAt'],
        DateTime(2026, 11, 23, 10, 31).toUtc(),
      );
    });

    test('every type survives an unchanged and a note-only edit '
        '(Codex, PR #35)', () async {
      final cases = <String, (EntryDraft, EntryExtras?)>{
        'expense': (draft(title: 'Lulu'), null),
        'partner expense': (draft(who: 'partner', note: 'gift'), null),
        'income': (draft(intent: 'income', category: 'salary'), null),
        'IQD expense': (draft(account: 'cash-iqd', amount: 25000), null),
        'past day': (draft(on: '2026-11-01'), null),
        'timed': (draft(time: '08:15'), null),
        'transfer': (draft(intent: 'transfer', to: 'savings'), null),
        'USD to IQD': (
          draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
          null,
        ),
        'IQD to USD': (
          draft(
            intent: 'transfer',
            account: 'cash-iqd',
            to: 'mine-usd',
            amount: 17050,
          ),
          null,
        ),
        'typed arriving amount': (
          draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
          const EntryExtras(toAmountMinor: 21000),
        ),
        'savings move': (draft(intent: 'savings_move', goal: 'trip'), null),
        'loan given': (
          draft(intent: 'loan_given', person: 'alex', loan: 'loan-usd'),
          null,
        ),
        'loan taken, name only': (
          EntryDraft.fromJson({
            ...draft(intent: 'loan_taken').toJson(),
            'personName': 'Sam',
          }),
          null,
        ),
        'repayment received, name and title': (
          EntryDraft.fromJson({
            ...draft(intent: 'repayment_received', title: 'Cash back').toJson(),
            'personName': 'Sam',
          }),
          null,
        ),
        'repayment made': (
          draft(intent: 'repayment_made', person: 'alex', loan: 'loan-usd'),
          null,
        ),
        'negative adjustment': (
          draft(intent: 'adjustment', account: 'mine-usd'),
          const EntryExtras(adjustmentSign: -1),
        ),
        'agent draft': (draft(origin: 'agent'), null),
      };
      for (final MapEntry(key: name, value: (saved, extras)) in cases.entries) {
        final id = await saveOne(repo, saved, extras: extras);
        final stored = {...store.transactions[id]!};
        final prefilled = draftFromTransaction(
          (await store.transaction(id))!,
          viewerUid: me,
        );
        final unchanged = await repo.editEntry(id, prefilled);
        expect(unchanged.failureOrNull, isNull, reason: name);
        expect(store.transactions[id], stored, reason: '$name: no write');
        final noted = await repo.editEntry(
          id,
          EntryDraft.fromJson({...prefilled.toJson(), 'note': 'checked'}),
        );
        expect(noted.failureOrNull, isNull, reason: name);
        expect(store.revisions[id]!.single['before'], {
          'note': stored['note'],
        }, reason: '$name: only the note changes');
      }
    });

    test("a converted arriving amount follows a new day's rate "
        '(Codex, PR #35)', () async {
      store.rates['2026-11-22'] = DayRate(
        day: '2026-11-22',
        rate: FxRate.forPair(FxPair.usdIqd, '1550').valueOrNull!,
      );
      EntryDraft iqdToUsd({String? on}) => draft(
        intent: 'transfer',
        account: 'cash-iqd',
        to: 'mine-usd',
        amount: 17050,
        on: on,
      );
      final converted = await saveOne(repo, iqdToUsd(on: '2026-11-20'));
      expect(store.transactions[converted]!['toAmountMinor'], 1000);
      await repo.editEntry(converted, iqdToUsd(on: '2026-11-23'));
      final moved = store.transactions[converted]!;
      expect((moved['fx']! as Map)['pairRate'], '1550');
      expect(moved['baseAmountMinor'], 1100);
      expect(moved['toAmountMinor'], 1100);

      // A typed arriving amount stays when the day moves.
      final typed = await saveOne(
        repo,
        iqdToUsd(on: '2026-11-20'),
        extras: const EntryExtras(toAmountMinor: 900),
      );
      await repo.editEntry(typed, iqdToUsd(on: '2026-11-23'));
      expect(store.transactions[typed]!['toAmountMinor'], 900);
      expect(store.transactions[typed]!['baseAmountMinor'], 1100);
    });

    test('an entered arriving amount equal to the conversion stays when '
        'the day moves (Codex, PR #35)', () async {
      store.rates['2026-11-22'] = DayRate(
        day: '2026-11-22',
        rate: FxRate.forPair(FxPair.usdIqd, '1550').valueOrNull!,
      );
      EntryDraft iqdToUsd(String on) => draft(
        intent: 'transfer',
        account: 'cash-iqd',
        to: 'mine-usd',
        amount: 17050,
        on: on,
      );
      // 17,050 IQD at 1,705 is exactly 10.00 USD, and the member typed 10.00.
      final typed = await saveOne(
        repo,
        iqdToUsd('2026-11-20'),
        extras: const EntryExtras(toAmountMinor: 1000),
      );
      final converted = await saveOne(repo, iqdToUsd('2026-11-20'));
      expect(store.transactions[typed]!['toAmountSource'], 'entered');
      expect(store.transactions[converted]!['toAmountSource'], 'rate');

      await repo.editEntry(typed, iqdToUsd('2026-11-23'));
      await repo.editEntry(converted, iqdToUsd('2026-11-23'));
      expect(store.transactions[typed]!['toAmountMinor'], 1000);
      expect(store.transactions[typed]!['toAmountSource'], 'entered');
      expect(store.transactions[converted]!['toAmountMinor'], 1100);
      expect(store.transactions[converted]!['toAmountSource'], 'rate');
    });

    test(
      'an entry saved before toAmountSource is judged by comparing',
      () async {
        store.rates['2026-11-22'] = DayRate(
          day: '2026-11-22',
          rate: FxRate.forPair(FxPair.usdIqd, '1550').valueOrNull!,
        );
        EntryDraft iqdToUsd(String on) => draft(
          intent: 'transfer',
          account: 'cash-iqd',
          to: 'mine-usd',
          amount: 17050,
          on: on,
        );
        final legacy = await saveOne(repo, iqdToUsd('2026-11-20'));
        final typed = await saveOne(
          repo,
          iqdToUsd('2026-11-20'),
          extras: const EntryExtras(toAmountMinor: 900),
        );
        for (final id in [legacy, typed]) {
          store.remoteEdit(id, {'toAmountSource': null});
        }
        await repo.editEntry(legacy, iqdToUsd('2026-11-23'));
        await repo.editEntry(typed, iqdToUsd('2026-11-23'));
        expect(store.transactions[legacy]!['toAmountMinor'], 1100);
        expect(store.transactions[typed]!['toAmountMinor'], 900);
      },
    );

    test('each write names the version it was built on', () async {
      final id = await saveOne(repo, draft());
      final created = store.transactions[id]!;
      expect(created['revId'], isA<String>());
      expect(created.containsKey('prevRevId'), true);
      expect(created['prevRevId'], isNull);
      await repo.editEntry(id, draft(amount: 99));
      final edited = store.transactions[id]!;
      expect(edited['prevRevId'], created['revId']);
      expect(edited['revId'], isNot(created['revId']));
      expect(store.revisions[id]!.single['id'], edited['revId']);
    });

    test('unknown and deleted entries', () async {
      expect(
        (await repo.editEntry('nope', draft())).failureOrNull,
        const TransactionNotFound(),
      );
      final id = await saveOne(repo, draft());
      await repo.deleteEntry(id);
      expect(
        (await repo.editEntry(id, draft(amount: 5))).failureOrNull,
        const TransactionDeleted(),
      );
    });
  });

  group('deleteEntry, restoreEntry and undoSave', () {
    test('delete soft-deletes with reversing increments', () async {
      final id = await saveOne(
        repo,
        draft(intent: 'transfer', account: 'mine-usd', to: 'cash-iqd'),
      );
      final result = await repo.deleteEntry(id);
      expect(result.valueOrNull, WriteAck.synced);
      final doc = store.transactions[id]!;
      expect(doc['deletedAt'], now.toUtc());
      expect(doc['rev'], 1);
      expect(store.balances, {'mine-usd': 0, 'cash-iqd': 0});
      expect(store.revisions[id]!.single['reason'], 'delete');
      expect(store.revisions[id]!.single['before'], {'deletedAt': null});
      expect(
        (await repo.deleteEntry(id)).failureOrNull,
        const TransactionDeleted(),
      );
    });

    test('restore re-applies and clears deletedAt', () async {
      final id = await saveOne(
        repo,
        draft(intent: 'repayment_made', person: 'alex', loan: 'loan-usd'),
      );
      await repo.deleteEntry(id);
      expect(store.outstanding['loan-usd'], 0);
      final result = await repo.restoreEntry(id);
      expect(result.valueOrNull, WriteAck.synced);
      final doc = store.transactions[id]!;
      expect(doc.containsKey('deletedAt'), true);
      expect(doc['deletedAt'], isNull);
      expect(doc['rev'], 2);
      expect(store.balances['joint-usd'], -1250);
      expect(store.outstanding['loan-usd'], -1250);
      expect(store.revisions[id]!.last['reason'], 'restore');
      expect(
        (await repo.restoreEntry(id)).failureOrNull,
        const TransactionNotDeleted(),
      );
    });

    test('undoSave deletes the whole group in batches', () async {
      final saved = (await repo.saveEntries([
        for (var i = 0; i < 12; i++) draft(id: 'd$i', amount: 100 + i),
      ])).valueOrNull!;
      final batches = store.committedBatches;
      final result = await repo.undoSave(saved);
      expect(result.valueOrNull, WriteAck.synced);
      expect(store.committedBatches - batches, 2, reason: '8 + 4 entries');
      expect(store.balances['joint-usd'], 0);
      for (final id in saved.txnIds) {
        expect(store.revisions[id]!.single['reason'], 'undo');
      }
      // A second undo has nothing left to do.
      expect((await repo.undoSave(saved)).valueOrNull, WriteAck.synced);
    });
  });

  group('two partners at once (DATA_MODEL 7)', () {
    test('an edit refused for a stale rev is re-applied on top', () async {
      final id = await saveOne(repo, draft());
      // The partner changes the note first (rev 0 → 1); this phone's cache
      // still holds rev 0 when it builds its edit.
      final stale = store.transactions[id]!;
      store.remoteEdit(id, {'note': 'from partner'});
      final staleStore = _StaleOnce(store, id, stale);
      final staleRepo = LedgerTransactionsRepository(staleStore);
      final result = await staleRepo.editEntry(id, draft(amount: 3000));
      expect(result.valueOrNull, WriteAck.synced);
      final doc = store.transactions[id]!;
      expect(doc['rev'], 2);
      expect(doc['amountMinor'], 3000);
      expect(store.balances['joint-usd'], -3000);
    });

    test('a refusal that is not a conflict is not retried', () async {
      final id = await saveOne(repo, draft());
      store.failNextCommit = const StoreFailure(
        StoreFailureKind.denied,
        'permission-denied',
      );
      final result = await repo.editEntry(id, draft(amount: 3000));
      expect(result.failureOrNull, const TransactionsNotAllowed());
      expect(store.transactions[id]!['rev'], 0);
    });
  });

  group('offline (DATA_MODEL 7)', () {
    test('save, edit and delete offline, then replay on reconnect', () async {
      store.goOnline(online: false);
      final saved = (await repo.saveEntries([
        draft(),
        draft(id: 'd2', account: 'cash-iqd', amount: 34100),
      ])).valueOrNull!;
      expect(saved.ack, WriteAck.queued);
      final [usd, iqd] = saved.txnIds;
      // Shown at once from the phone's cache.
      expect(store.balances, {'joint-usd': -1250, 'cash-iqd': -34100});
      expect(
        (await repo.editEntry(usd, draft(amount: 500))).valueOrNull,
        WriteAck.queued,
      );
      expect((await repo.deleteEntry(iqd)).valueOrNull, WriteAck.queued);
      expect(store.balances, {'joint-usd': -500, 'cash-iqd': 0});
      expect(store.serverTransactions, isEmpty);
      expect(store.pendingBatches, 3);

      store.goOnline(online: true);
      expect(store.pendingBatches, 0);
      expect(store.serverBalances, {'joint-usd': -500, 'cash-iqd': 0});
      expect(store.serverTransactions[usd]!['rev'], 1);
      expect(store.serverTransactions[iqd]!['deletedAt'], isNotNull);
    });

    test('a queued edit that loses to the partner is re-applied', () async {
      final id = await saveOne(repo, draft());
      final late = <LateWriteFailure>[];
      repo.lateFailures.listen(late.add);
      store.goOnline(online: false);
      await repo.editEntry(id, draft(amount: 4000));
      // Meanwhile the partner's edit reaches the server.
      store
        ..remoteEdit(id, {'note': 'partner'})
        ..goOnline(online: true);
      await pumpEventQueue();
      final doc = store.serverTransactions[id]!;
      expect(doc['rev'], 2, reason: 'partner 1, re-applied edit 2');
      expect(doc['amountMinor'], 4000);
      expect(store.serverBalances['joint-usd'], -4000);
      expect(late, isEmpty);
    });

    test('a queued delete built on a refused edit is rebuilt too '
        '(Codex, PR #35)', () async {
      final id = await saveOne(repo, draft(amount: 100));
      final late = <LateWriteFailure>[];
      repo.lateFailures.listen(late.add);
      store.goOnline(online: false);
      await repo.editEntry(id, draft(amount: 200));
      await repo.deleteEntry(id);
      // The partner's note reaches the server first: the queued edit (rev 1)
      // is refused, and the delete (rev 2) must not land on the partner's
      // rev 1 with the edit's +200.
      store
        ..remoteEdit(id, {'note': 'partner'})
        ..goOnline(online: true);
      await pumpEventQueue();
      final doc = store.serverTransactions[id]!;
      expect(doc['deletedAt'], isNotNull);
      expect(store.serverBalances['joint-usd'], 0);
      expect(late, isEmpty);
    });

    group('across an app restart (Codex, PR #35)', () {
      late MemoryWriteJournal journal;
      late List<LateWriteFailure> late;

      setUp(() {
        journal = MemoryWriteJournal();
        repo = LedgerTransactionsRepository(store, journal: journal);
        late = [];
      });

      /// Closes the app with the queue still on the phone, opens it again,
      /// and lets [meanwhile] happen on the server before reconnecting.
      Future<LedgerTransactionsRepository> restartAndReconnect(
        void Function() meanwhile,
      ) async {
        store.restart();
        final next = LedgerTransactionsRepository(store, journal: journal)
          ..lateFailures.listen(late.add);
        meanwhile();
        final resumed = next.resumePending();
        store.goOnline(online: true);
        await resumed;
        await pumpEventQueue();
        return next;
      }

      test('a queued edit refused after a restart is re-applied', () async {
        final id = await saveOne(repo, draft());
        store.goOnline(online: false);
        expect(
          (await repo.editEntry(id, draft(amount: 4000))).valueOrNull,
          WriteAck.queued,
        );
        expect(journal.entries.single.op, 'edit');
        await restartAndReconnect(
          () => store.remoteEdit(id, {'note': 'partner'}),
        );
        final doc = store.serverTransactions[id]!;
        expect(doc['amountMinor'], 4000);
        expect(doc['rev'], 2);
        expect(store.serverBalances['joint-usd'], -4000);
        expect(journal.entries, isEmpty);
        expect(late, isEmpty);
      });

      test('a queued delete refused after a restart is re-applied', () async {
        final id = await saveOne(repo, draft());
        store.goOnline(online: false);
        await repo.deleteEntry(id);
        await restartAndReconnect(
          () => store.remoteEdit(id, {'note': 'partner'}),
        );
        expect(store.serverTransactions[id]!['deletedAt'], isNotNull);
        expect(store.serverBalances['joint-usd'], 0);
        expect(journal.entries, isEmpty);
      });

      test('a queued change that landed is only cleared', () async {
        final id = await saveOne(repo, draft());
        store.goOnline(online: false);
        await repo.editEntry(id, draft(amount: 4000));
        await restartAndReconnect(() {});
        expect(store.serverTransactions[id]!['rev'], 1);
        expect(store.serverBalances['joint-usd'], -4000);
        expect(journal.entries, isEmpty);
        expect(late, isEmpty);
      });

      test('a refusal that is not a conflict is reported', () async {
        final id = await saveOne(repo, draft(account: 'mine-usd'));
        store.goOnline(online: false);
        await repo.editEntry(id, draft(account: 'mine-usd', amount: 4000));
        await restartAndReconnect(
          () => store.accounts['mine-usd'] = const LedgerAccount(
            id: 'mine-usd',
            currency: Currency.usd,
            visibleTo: [partner],
          ),
        );
        expect(store.serverTransactions[id]!['rev'], 0);
        expect(late.single.txnIds, [id]);
        expect(late.single.failure, const TransactionsNotAllowed());
        expect(journal.entries, isEmpty);
      });

      test("another member's sign-in keeps the record for its owner", () async {
        final id = await saveOne(repo, draft());
        store.goOnline(online: false);
        await repo.editEntry(id, draft(amount: 4000));
        // The app restarts with the partner signed in on this phone.
        store.restart();
        final next = LedgerTransactionsRepository(store, journal: journal)
          ..lateFailures.listen(late.add);
        store
          ..remoteEdit(id, {'note': 'partner'})
          ..scope = const LedgerScope(householdId: 'h1', uid: partner);
        final resumed = next.resumePending();
        store.goOnline(online: true);
        await resumed;
        expect(journal.entries, hasLength(1), reason: 'not theirs to resume');
        expect(store.serverTransactions[id]!['amountMinor'], 1250);

        // The owner signs in again: their change is re-applied.
        store.scope = const LedgerScope(householdId: 'h1', uid: me);
        await next.resumePending();
        await pumpEventQueue();
        expect(store.serverTransactions[id]!['amountMinor'], 4000);
        expect(store.serverBalances['joint-usd'], -4000);
        expect(journal.entries, isEmpty);
        expect(late, isEmpty);
      });

      test('a stop while re-applying leaves the change to the next launch '
          '(Codex, PR #35)', () async {
        final id = await saveOne(repo, draft());
        store.goOnline(online: false);
        await repo.editEntry(id, draft(amount: 4000));
        store
          ..restart()
          ..remoteEdit(id, {'note': 'partner'});
        // Next launch: the app stops (here: the journal write throws) after
        // the stale record was read and before its re-apply is recorded.
        final crashing = _StopsOnPut(journal);
        final stopped = LedgerTransactionsRepository(store, journal: crashing);
        final resumed = stopped.resumePending();
        store.goOnline(online: true);
        await expectLater(resumed, throwsA(isA<_Stopped>()));
        expect(store.serverTransactions[id]!['amountMinor'], 1250);

        // The launch after that still finds the change and re-applies it.
        final next = LedgerTransactionsRepository(store, journal: journal)
          ..lateFailures.listen(late.add);
        await next.resumePending();
        await pumpEventQueue();
        expect(store.serverTransactions[id]!['amountMinor'], 4000);
        expect(store.serverBalances['joint-usd'], -4000);
        expect(journal.entries, isEmpty);
        expect(late, isEmpty);
      });

      test('synced writes leave nothing in the journal', () async {
        final id = await saveOne(repo, draft());
        await repo.editEntry(id, draft(amount: 5));
        await repo.deleteEntry(id);
        await repo.restoreEntry(id);
        expect(journal.entries, isEmpty);
      });
    });

    test('a queued save the server refuses is reported', () async {
      final late = <LateWriteFailure>[];
      repo.lateFailures.listen(late.add);
      store.goOnline(online: false);
      final id = await saveOne(repo, draft(account: 'mine-usd'));
      // The account becomes invisible before the queue reaches the server.
      store.accounts['mine-usd'] = const LedgerAccount(
        id: 'mine-usd',
        currency: Currency.usd,
        visibleTo: [partner],
      );
      store.goOnline(online: true);
      await pumpEventQueue();
      expect(store.serverTransactions, isEmpty);
      expect(late.single.txnIds, [id]);
      expect(late.single.failure, const TransactionsNotAllowed());
    });
  });

  test('a random mix of writes always reconciles', () async {
    final ids = <String>[];
    final accounts = ['joint-usd', 'mine-usd', 'cash-iqd', 'savings'];
    for (var i = 0; i < 60; i++) {
      final account = accounts[i % accounts.length];
      final currency = store.accounts[account]!.currency.code;
      switch (i % 5) {
        case 0 || 1:
          ids.add(
            await saveOne(
              repo,
              draft(account: account, currency: currency, amount: 100 + i),
            ),
          );
        case 2 when ids.isNotEmpty:
          await repo.editEntry(
            ids[i % ids.length],
            draft(
              intent: 'transfer',
              account: account,
              to: accounts[(i + 1) % accounts.length],
              amount: 7 * i + 1,
            ),
          );
        case 3 when ids.isNotEmpty:
          await repo.deleteEntry(ids[i % ids.length]);
        case _ when ids.isNotEmpty:
          await repo.restoreEntry(ids[(i * 3) % ids.length]);
      }
      expectReconciled(store);
    }
  });
}

/// The store, except that the first read of `id` returns `stale`: the
/// phone's cache before the partner's edit arrived.
final class _StaleOnce implements LedgerStore {
  new(this._inner, this._id, this._stale);

  final MemoryLedgerStore _inner;
  final String _id;
  Map<String, Object?>? _stale;

  @override
  LedgerScope? get scope => _inner.scope;

  @override
  DateTime now() => _inner.now();

  @override
  String newId() => _inner.newId();

  @override
  Future<LedgerHousehold?> household() => _inner.household();

  @override
  Future<LedgerAccount?> account(String id) => _inner.account(id);

  @override
  Future<LedgerCategory?> category(String id) => _inner.category(id);

  @override
  Future<LedgerLoan?> loan(String id) => _inner.loan(id);

  @override
  Future<bool> hasPerson(String id) => _inner.hasPerson(id);

  @override
  Future<String?> goalAccount(String id) => _inner.goalAccount(id);

  @override
  Future<DayRate?> rateOn(String day) => _inner.rateOn(day);

  @override
  Future<LedgerTransaction?> transaction(String id, {bool fresh = false}) {
    final stale = _stale;
    if (id == _id && stale != null && !fresh) {
      _stale = null;
      return Future.value(transactionFromFields(id, stale));
    }
    return _inner.transaction(id, fresh: fresh);
  }

  @override
  Future<void> settle() => _inner.settle();

  @override
  Future<bool> hasRevision(String txnId, String revId) =>
      _inner.hasRevision(txnId, revId);

  @override
  Future<Result<WriteAck, StoreFailure>> commit(
    LedgerPlan plan, {
    void Function(StoreFailure failure)? onLateFailure,
  }) => _inner.commit(plan, onLateFailure: onLateFailure);
}

/// The app stopping: the journal throws on its next write.
final class _Stopped implements Exception;

/// [WriteJournal] over [_inner] whose first write "stops the app".
final class _StopsOnPut implements WriteJournal {
  new(this._inner);

  final WriteJournal _inner;

  @override
  List<PendingRevision> get entries => _inner.entries;

  @override
  Future<void> put(PendingRevision entry) => throw _Stopped();

  @override
  Future<void> remove(String revId) => _inner.remove(revId);
}
