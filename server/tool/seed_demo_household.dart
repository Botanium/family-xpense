/// Writes the demo household (`lib/runtime/demo_household.dart`) into the
/// Firestore emulator in the DATA_MODEL shape, so the agent can run its
/// production path locally: Firestore reader, Firestore session store and
/// the `/decide` classifier.
///
///     firebase emulators:exec --project demo-xpense \
///       --config test/emulator/firebase.json --only firestore \
///       'dart run tool/seed_demo_household.dart && genkit flow:run …'
///
/// Refuses to run without `FIRESTORE_EMULATOR_HOST`.
library;

import 'dart:io';

import 'package:clock/clock.dart';
import 'package:google_cloud_firestore/google_cloud_firestore.dart' as fs;
import 'package:xpense_agent/runtime/demo_household.dart';
import 'package:xpense_agent/tools/local_day.dart';

Future<void> main() async {
  if ((Platform.environment['FIRESTORE_EMULATOR_HOST'] ?? '').isEmpty) {
    stderr.writeln('FIRESTORE_EMULATOR_HOST is not set; refusing to write.');
    exitCode = 2;
    return;
  }
  final db = fs.Firestore(
    settings: const fs.Settings(projectId: 'demo-xpense'),
  );
  final h = demoHousehold(localToday(const Clock(), 'Asia/Baghdad').iso);
  const root = 'households/$demoHid';
  final writes = <String, Map<String, Object?>>{
    root: {
      'name': 'Demo',
      'baseCurrency': h.profile.baseCurrency,
      'timeZone': h.profile.timeZone,
      'memberIds': h.profile.memberIds,
      'weekStart': h.profile.weekStart,
      'rateKind': h.profile.rateKind,
    },
    for (final m in h.members) ...{
      'users/${m.uid}': {'householdId': demoHid, 'locale': 'en'},
      '$root/members/${m.uid}': {
        'displayName': m.displayName,
        'role': m.role,
        'privacyMode': 'smart',
      },
    },
    for (final (:item, :visibleTo) in h.accounts)
      '$root/accounts/${item.id}': {
        'name': item.name,
        'kind': item.kind,
        'currency': item.currency,
        'scope': item.scope,
        'ownerUid': item.ownerUid,
        'sharedWithPartner': visibleTo.length > 1,
        'visibleTo': visibleTo,
        'balanceMinor': item.balanceMinor,
        'archived': item.archived,
        'order': item.order,
      },
    for (final c in h.categories)
      '$root/categories/${c.id}': {
        'slug': c.slug,
        'names': {'en': c.name},
        'kind': c.kind,
        'parentId': c.parentId,
        'archived': false,
        'system': true,
      },
    for (final (:item, :visibleTo) in h.people)
      '$root/people/${item.id}': {
        'name': item.name,
        'aliases': item.aliases,
        'visibleTo': visibleTo,
      },
    for (final (:item, :visibleTo) in h.loans)
      '$root/loans/${item.id}': {
        'direction': item.direction,
        'kind': 'personal',
        'personId': item.personId,
        'principalMinor': item.principalMinor,
        'outstandingMinor': item.outstandingMinor,
        'currency': item.currency,
        'status': item.status,
        'visibleTo': visibleTo,
      },
    for (final (:item, :visibleTo) in h.budgets)
      '$root/budgets/${item.id}': {
        'categoryId': item.categoryId,
        'period': 'monthly',
        'limitMinor': item.limitMinor,
        'visibleTo': visibleTo,
      },
    for (final (:item, :visibleTo) in h.transactions)
      '$root/transactions/${item.id}': {
        'type': item.type,
        'amountMinor': item.amountMinor,
        'currency': item.currency,
        'baseAmountMinor': item.baseAmountMinor,
        'accountId': item.accountId,
        'toAccountId': item.toAccountId,
        'categoryId': item.categoryId,
        'whoUid': item.whoUid,
        'whoScope': item.whoScope,
        'occurredOn': item.occurredOn,
        'title': item.title,
        'visibleTo': visibleTo,
        'source': 'manual',
      },
    for (final r in h.fxRates)
      '$root/fxRates/${r.date}': {'usdIqd': r.usdIqd, 'kind': r.kind},
  };
  for (final MapEntry(:key, :value) in writes.entries) {
    await db.doc(key).set(value);
  }
  stdout.writeln('seeded ${writes.length} documents under $root');
}
