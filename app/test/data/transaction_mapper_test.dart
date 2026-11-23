// The stored form of a transaction (DATA_MODEL 2.5) and its draft for the
// edit form.
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/mappers/transaction_mapper.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  final transfer = LedgerTransaction(
    id: 't1',
    type: LedgerType.transfer,
    amountMinor: 10000,
    currency: Currency.usd,
    accountId: 'usd',
    toAccountId: 'iqd',
    toAmountMinor: 170500,
    baseAmountMinor: 10000,
    fx: const StoredFx(
      pair: 'USD/IQD',
      pairRate: '1705',
      source: 'market',
      asOf: '2026-11-20',
    ),
    whoScope: WhoScope.member,
    whoUid: 'me',
    occurredAt: DateTime.utc(2026, 11, 23, 7, 30),
    occurredOn: '2026-11-23',
    visibleTo: const ['me', 'partner'],
    title: 'To cash',
    groupId: 'g1',
    source: EntrySource.chat,
    rev: 3,
    createdBy: 'me',
  );

  test('content holds every content field, nulls included', () {
    final content = transactionContent(transfer);
    expect(content.keys.toList(), transactionContentFields);
    expect(content['adjustmentSign'], isNull);
    expect(content['fx'], {
      'pair': 'USD/IQD',
      'pairRate': '1705',
      'source': 'market',
      'asOf': '2026-11-20',
    });
  });

  test('round-trips through the stored fields', () {
    final stored = {
      ...transactionContent(transfer),
      'rev': 3,
      'createdBy': 'me',
      'deletedAt': null,
    };
    expect(transactionFromFields('t1', stored), transfer);
  });

  test('a pending deletedAt reads as deleted', () {
    final stored = {...transactionContent(transfer), 'deletedAt': Object()};
    final read = transactionFromFields('t1', stored)!;
    expect(read.deleted, true);
    expect(read.deletePending, true);
    expect(read.line.deleted, true);
  });

  test('malformed documents read as null', () {
    expect(transactionFromFields('t', {'type': 'gift'}), isNull);
    expect(
      transactionFromFields('t', {
        ...transactionContent(transfer),
        'occurredAt': '2026-11-23',
      }),
      isNull,
    );
  });

  test('a draft for the edit form says who from the viewer side', () {
    final mine = draftFromTransaction(transfer, viewerUid: 'me');
    expect(mine.intent, 'transfer');
    expect(mine.who, 'me');
    expect(mine.toAccountId, 'iqd');
    expect(mine.fx?.pairRate, '1705');
    expect(mine.fx?.baseAmountMinor, 10000);
    expect(draftFromTransaction(transfer, viewerUid: 'partner').who, 'partner');
    final move = LedgerTransaction(
      id: 't2',
      type: LedgerType.transfer,
      amountMinor: 1,
      currency: Currency.usd,
      accountId: 'a',
      toAccountId: 'savings',
      goalId: 'trip',
      baseAmountMinor: 1,
      whoScope: WhoScope.joint,
      occurredAt: DateTime.utc(2026),
      occurredOn: '2026-01-01',
      visibleTo: const ['me'],
    );
    final draft = draftFromTransaction(move, viewerUid: 'me');
    expect(draft.intent, 'savings_move');
    expect(draft.who, 'joint');
    expect(draft.title, isNull);
  });
}
