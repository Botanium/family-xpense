// The pure parts of Activity (WP-22): filters to queries, day groups and
// their net, search, the question test, and the feed adapters' helpers.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_fake.dart';
import 'package:xpense_app/data/read/activity_reader.dart';
import 'package:xpense_app/data/read/activity_reader_firestore.dart';
import 'package:xpense_app/data/read/activity_reader_memory.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/activity/activity_model.dart';
import 'package:xpense_shared/xpense_shared.dart';

LedgerTransaction txn(
  String id, {
  LedgerType type = LedgerType.expense,
  int amount = 1000,
  int? base,
  String day = '2026-11-22',
  String title = '',
  String? note,
  String? who = 'me',
  Currency currency = Currency.usd,
  List<String> visibleTo = const ['me'],
}) => LedgerTransaction(
  id: id,
  type: type,
  amountMinor: amount,
  currency: currency,
  accountId: 'a',
  baseAmountMinor: base ?? amount,
  whoScope: WhoScope.member,
  whoUid: who,
  occurredAt: DateTime.parse('${day}T12:00:00Z'),
  occurredOn: day,
  visibleTo: visibleTo,
  title: title,
  note: note,
);

Map<String, Object?> stored(LedgerTransaction t, {Object? deletedAt}) => {
  'type': t.type.wire,
  'amountMinor': t.amountMinor,
  'currency': t.currency.code,
  'accountId': t.accountId,
  'baseAmountMinor': t.baseAmountMinor,
  'whoScope': 'member',
  'whoUid': t.whoUid,
  'occurredAt': t.occurredAt,
  'occurredOn': t.occurredOn,
  'title': t.title,
  'visibleTo': t.visibleTo,
  'deletedAt': deletedAt,
};

void main() {
  group('filters', () {
    test('each filter is one indexed query (DATA_MODEL 6)', () {
      ActivityQuery? q(ActivityFilter f) =>
          f.query(limit: 50, viewerUid: 'me', partnerUid: 'sam');
      expect(q(ActivityFilter.all), const ActivityQuery(limit: 50));
      expect(q(ActivityFilter.out)!.types, {LedgerType.expense});
      expect(q(ActivityFilter.inflow)!.types, {LedgerType.income});
      expect(q(ActivityFilter.loans)!.types, ActivityFilter.loanTypes);
      expect(q(ActivityFilter.you)!.whoUid, 'me');
      expect(q(ActivityFilter.partner)!.whoUid, 'sam');
      expect(
        ActivityFilter.partner.query(
          limit: 50,
          viewerUid: 'me',
          partnerUid: null,
        ),
        isNull,
      );
    });

    test('a query never combines a type and a member filter', () {
      expect(
        () => ActivityQuery(limit: 1, types: const {}, whoUid: 'x'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('day groups', () {
    test('group by day in order; the net is income minus spending', () {
      final days = groupByDay([
        txn('1', amount: 4280),
        txn('2', type: LedgerType.loanGiven, amount: 30000),
        txn('3', type: LedgerType.income, amount: 320000),
        txn('4', amount: 140000),
        txn('5', day: '2026-11-21', amount: 5810),
        txn('6', day: '2026-11-21', type: LedgerType.income, amount: 15000),
        txn('7', day: '2026-11-20', type: LedgerType.transfer),
      ]);
      expect(days.map((d) => d.day), [
        '2026-11-22',
        '2026-11-21',
        '2026-11-20',
      ]);
      expect(days[0].netMinor, 175720);
      expect(days[1].netMinor, 9190);
      expect(days[0].entries.map((t) => t.id), ['1', '2', '3', '4']);
      // A day of moves only shows no net.
      expect(days[2].hasNet, isFalse);
    });

    test('the net uses the base amount, not the entry currency', () {
      final days = groupByDay([
        txn('iqd', amount: 41175, base: 2415, currency: Currency.iqd),
      ]);
      expect(days.single.netMinor, -2415);
    });

    test('flatten: a header, then rows; the last row of a day knows it', () {
      final items = flatten(
        groupByDay([txn('1'), txn('2'), txn('3', day: '2026-11-21')]),
      );
      expect(items.map((i) => i.runtimeType), [
        ActivityDayHeader,
        ActivityEntryItem,
        ActivityEntryItem,
        ActivityDayHeader,
        ActivityEntryItem,
      ]);
      expect((items[1] as ActivityEntryItem).last, isFalse);
      expect((items[2] as ActivityEntryItem).last, isTrue);
    });

    test('amount signs', () {
      expect(amountSignOf(txn('a')), AmountSign.minus);
      expect(amountSignOf(txn('a', type: LedgerType.income)), AmountSign.plus);
      for (final t in [
        LedgerType.transfer,
        LedgerType.loanGiven,
        LedgerType.loanTaken,
        LedgerType.repaymentMade,
        LedgerType.repaymentReceived,
        LedgerType.adjustment,
      ]) {
        expect(amountSignOf(txn('a', type: t)), AmountSign.none, reason: '$t');
      }
    });
  });

  group('search', () {
    final costco = SearchText.of(
      txn('c', amount: 142080, title: 'Costco', note: 'Paper towels'),
      categoryName: 'Groceries',
    );
    final dinars = SearchText.of(
      txn('d', amount: 41175, currency: Currency.iqd, title: 'Pharmacy'),
    );

    test('title, note and category, any case, every word', () {
      expect(searchMatches(costco, 'costco'), isTrue);
      expect(searchMatches(costco, 'TOWELS'), isTrue);
      expect(searchMatches(costco, 'groceries costco'), isTrue);
      expect(searchMatches(costco, 'costco fuel'), isFalse);
      expect(searchMatches(costco, '  '), isTrue);
    });

    test('amounts as shown, with or without grouping', () {
      expect(searchMatches(costco, '1420.80'), isTrue);
      expect(searchMatches(costco, '1,420'), isTrue);
      expect(searchMatches(costco, '1420.8'), isTrue);
      expect(searchMatches(costco, '99'), isFalse);
      expect(searchMatches(dinars, '41,175'), isTrue);
      expect(searchMatches(dinars, '41175'), isTrue);
    });

    test('questions go to Ask; searches stay', () {
      for (final q in [
        'How much did we spend on food?',
        'how much on groceries this month',
        'What did Sam spend on fuel',
        'did we pay rent',
        'show me June',
        'groceries?',
      ]) {
        expect(looksLikeQuestion(q), isTrue, reason: q);
      }
      for (final q in [
        'costco',
        'rent',
        'paper towels',
        '42.80',
        '?',
        '',
        'how much',
      ]) {
        expect(looksLikeQuestion(q), isFalse, reason: q);
      }
    });
  });

  group('memory reader', () {
    test(
      'only live entries the viewer can see, newest first, limited',
      () async {
        final fields = {
          'old': stored(txn('old', day: '2026-11-01')),
          'new': stored(txn('new')),
          'mid': stored(txn('mid', day: '2026-11-10')),
          'gone': stored(txn('gone'), deletedAt: DateTime.utc(2026, 11, 22)),
          'hidden': stored(txn('hidden', visibleTo: const ['sam'])),
          'income': stored(txn('income', type: LedgerType.income)),
        };
        final feed = MemoryActivityReader(read: () => fields, viewerUid: 'me');
        final window = await feed.watch(const ActivityQuery(limit: 3)).first;
        expect(window.entries.map((t) => t.id), ['new', 'income', 'mid']);
        expect(window.hasMore, isTrue);

        final out = await feed
            .watch(const ActivityQuery(limit: 10, types: {LedgerType.expense}))
            .first;
        expect(out.entries.map((t) => t.id), ['new', 'mid', 'old']);
        expect(out.hasMore, isFalse);
      },
    );

    test('emits again on change', () async {
      final fields = <String, Map<String, Object?>>{};
      final feed = MemoryActivityReader(read: () => fields, viewerUid: 'me');
      final windows = feed.watch(const ActivityQuery(limit: 10));
      final seen = <int>[];
      final sub = windows.listen((w) => seen.add(w.entries.length));
      await pumpEventQueue();
      fields['a'] = stored(txn('a'));
      feed.changed();
      await pumpEventQueue();
      expect(seen, [0, 1]);
      await sub.cancel();
    });
  });

  group('Firestore reader helpers', () {
    test('timestamps become UTC DateTimes, nested too', () {
      final at = DateTime.utc(2026, 11, 22, 9);
      final plain = FirestoreActivityReader.plainFields({
        'occurredAt': Timestamp.fromDate(at),
        'deletedAt': null,
        'ai': {
          'at': Timestamp.fromDate(at),
          'list': [Timestamp.fromDate(at)],
        },
      });
      expect(plain['occurredAt'], at);
      expect(plain['deletedAt'], isNull);
      expect((plain['ai']! as Map)['at'], at);
      expect(((plain['ai']! as Map)['list'] as List).single, at);
    });

    test('read errors become typed failures', () {
      expect(
        FirestoreActivityReader.failureOf(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ),
        ),
        const ActivityNotAllowed(),
      );
      expect(
        FirestoreActivityReader.failureOf(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        const ActivityReadFailed('unavailable'),
      );
      expect(
        FirestoreActivityReader.failureOf(StateError('x')),
        const ActivityReadFailed('StateError'),
      );
    });

    test('only filtered queries can fall back to filtering on the phone', () {
      expect(
        FirestoreActivityReader.hasFilter(const ActivityQuery(limit: 1)),
        isFalse,
      );
      expect(
        FirestoreActivityReader.hasFilter(
          const ActivityQuery(limit: 1, whoUid: 'me'),
        ),
        isTrue,
      );
    });
  });

  group('Firestore reader scope and retries (Codex review, PR #38)', () {
    const household = FakeHouseholdRepository.sampleHousehold;
    const other = HouseholdSummary(
      id: 'other-household',
      name: 'Other',
      baseCurrency: Currency.usd,
      memberCount: 1,
    );
    final denied = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    const window = ActivityWindow(entries: [], hasMore: true);

    // Reports go to the console, not to the test.
    late FlutterExceptionHandler? saved;
    setUp(() {
      saved = FlutterError.onError;
      FlutterError.onError = (_) {};
    });
    tearDown(() => FlutterError.onError = saved);

    test('a listen refused right after joining is tried again', () async {
      final memberships = StreamController<Membership>();
      final opened = <String>[];
      final windows = <ActivityWindow>[];
      final errors = <Object>[];
      final sub = FirestoreActivityReader.scoped(
        membership: memberships.stream,
        uid: () => 'me',
        query: const ActivityQuery(limit: 50),
        retryDelay: const Duration(milliseconds: 1),
        open: (hid, uid, {required serverFilter}) {
          opened.add(hid);
          // The founding batch has not reached the server yet.
          return opened.length < 3
              ? Stream.error(denied)
              : Stream.value(window);
        },
      ).listen(windows.add, onError: errors.add);
      memberships.add(const InHousehold(household));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(opened, [household.id, household.id, household.id]);
      expect(windows, [window]);
      expect(errors, isEmpty);
      await sub.cancel();
      await memberships.close();
    });

    test(
      'after the retries, the error shows; the same scope listens again',
      () async {
        final memberships = StreamController<Membership>();
        var refuse = true;
        var opens = 0;
        final windows = <ActivityWindow>[];
        final errors = <Object>[];
        final sub = FirestoreActivityReader.scoped(
          membership: memberships.stream,
          uid: () => 'me',
          query: const ActivityQuery(limit: 50),
          retries: 2,
          retryDelay: const Duration(milliseconds: 1),
          open: (hid, uid, {required serverFilter}) {
            opens++;
            return refuse ? Stream.error(denied) : Stream.value(window);
          },
        ).listen(windows.add, onError: errors.add);
        memberships.add(const InHousehold(household));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(opens, 3); // the first try and two retries
        expect(errors, [const ActivityNotAllowed()]);

        // The same household again (a membership refresh) is no longer
        // ignored once the listener has ended.
        refuse = false;
        memberships.add(const InHousehold(household));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(opens, 4);
        expect(windows, [window]);
        await sub.cancel();
        await memberships.close();
      },
    );

    test('a retry from an old household is dropped after a switch', () async {
      final memberships = StreamController<Membership>();
      final opened = <String>[];
      final sub = FirestoreActivityReader.scoped(
        membership: memberships.stream,
        uid: () => 'me',
        query: const ActivityQuery(limit: 50),
        retryDelay: const Duration(milliseconds: 20),
        open: (hid, uid, {required serverFilter}) {
          opened.add(hid);
          return hid == household.id
              ? Stream.error(denied)
              : Stream.value(window);
        },
      ).listen((_) {}, onError: (_) {});
      memberships.add(const InHousehold(household));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      memberships.add(const InHousehold(other));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(opened, [household.id, other.id]);
      await sub.cancel();
      await memberships.close();
    });

    test('a filter without an index falls back to the phone', () async {
      final memberships = StreamController<Membership>();
      final calls = <bool>[];
      final sub = FirestoreActivityReader.scoped(
        membership: memberships.stream,
        uid: () => 'me',
        query: const ActivityQuery(limit: 50, whoUid: 'me'),
        open: (hid, uid, {required serverFilter}) {
          calls.add(serverFilter);
          return serverFilter
              ? Stream.error(
                  FirebaseException(
                    plugin: 'cloud_firestore',
                    code: 'failed-precondition',
                  ),
                )
              : Stream.value(window);
        },
      ).listen((_) {});
      memberships.add(const InHousehold(household));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, [true, false]);
      await sub.cancel();
      await memberships.close();
    });
  });
}
