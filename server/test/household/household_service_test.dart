import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/household/household_failure.dart';
import 'package:xpense_agent/household/household_service.dart';
import 'package:xpense_agent/household/invite_code.dart';
import 'package:xpense_agent/household/rate_limiter.dart';

import '../support/fakes.dart';

Matcher refusedWith(HouseholdFailure failure) => throwsA(
  isA<HouseholdRejection>().having((e) => e.failure, 'failure', failure),
);

void main() {
  late FakeDocumentStore docs;
  late DateTime now;
  late HouseholdService service;

  setUp(() {
    docs = FakeDocumentStore()
      ..seedMember(uid: 'owner', hid: 'h1')
      ..docs['households/h1']!['name'] = 'Our home';
    now = DateTime.utc(2026, 11, 22, 9);
    service = HouseholdService(
      docs,
      clock: Clock(() => now),
      random: Random(42),
    );
  });

  Map<String, Map<String, Object?>> invites() => {
    for (final MapEntry(:key, :value) in docs.docs.entries)
      if (key.startsWith('invites/')) key: value,
  };

  group('createInvite', () {
    test('stores only the hash, for 7 days, and returns the code', () async {
      final invite = await service.createInvite(uid: 'owner', hid: 'h1');

      expect(normalizeInviteCode(invite.code), invite.code);
      expect(invite.expiresAt, now.add(const Duration(days: 7)));
      expect(invite.link, 'xpense://join?code=${invite.code}');
      expect(invites().keys, ['invites/${inviteCodeHash(invite.code)}']);
      expect(invites().values.single, {
        'hid': 'h1',
        'createdBy': 'owner',
        'createdAt': now,
        'expiresAt': now.add(const Duration(days: 7)),
        'usedBy': null,
        'usedAt': null,
        'schemaVersion': 1,
      });
      // The code appears nowhere in the database.
      expect(jsonEncode(docs.docs.toString()), isNot(contains(invite.code)));
    });

    test('a new invite replaces the unused earlier one', () async {
      final first = await service.createInvite(uid: 'owner', hid: 'h1');
      final second = await service.createInvite(uid: 'owner', hid: 'h1');
      expect(second.code, isNot(first.code));
      expect(invites().keys, ['invites/${inviteCodeHash(second.code)}']);
    });

    test("used invites and other households' invites are kept", () async {
      docs.docs['invites/used'] = {'hid': 'h1', 'usedBy': 'someone'};
      docs.docs['invites/other'] = {'hid': 'h2', 'usedBy': null};
      await service.createInvite(uid: 'owner', hid: 'h1');
      expect(invites().keys, containsAll(['invites/used', 'invites/other']));
      expect(invites(), hasLength(3));
    });

    test('a full household gets no invite', () async {
      docs.docs['households/h1']!['memberIds'] = ['owner', 'partner'];
      await expectLater(
        service.createInvite(uid: 'owner', hid: 'h1'),
        refusedWith(HouseholdFailure.householdFull),
      );
      expect(invites(), isEmpty);
    });

    test('someone the household does not list gets no invite', () async {
      await expectLater(
        service.createInvite(uid: 'stranger', hid: 'h1'),
        refusedWith(HouseholdFailure.notMember),
      );
      await expectLater(
        service.createInvite(uid: 'owner', hid: 'missing'),
        refusedWith(HouseholdFailure.notMember),
      );
    });

    test('at most 10 an hour per user', () async {
      for (var i = 0; i < 10; i++) {
        await service.createInvite(uid: 'owner', hid: 'h1');
      }
      await expectLater(
        service.createInvite(uid: 'owner', hid: 'h1'),
        refusedWith(HouseholdFailure.rateLimited),
      );
      now = now.add(const Duration(hours: 1));
      await service.createInvite(uid: 'owner', hid: 'h1');
    });
  });

  group('join', () {
    late String code;

    setUp(() async {
      code = (await service.createInvite(uid: 'owner', hid: 'h1')).code;
    });

    test('adds the partner in one transaction', () async {
      final commitsBefore = docs.commits;
      final joined = await service.join(
        uid: 'partner',
        code: code,
        displayName: '  Sam  ',
      );

      expect(joined.hid, 'h1');
      expect(joined.name, 'Our home');
      // One for the rate limiter, one for the join.
      expect(docs.commits - commitsBefore, 2);
      expect(docs.docs['households/h1']!['memberIds'], ['owner', 'partner']);
      expect(docs.docs['households/h1/members/partner'], {
        'displayName': 'Sam',
        'initial': 'S',
        'role': 'partner',
        'privacyMode': 'smart',
        'notificationPrefs': <String, Object?>{},
        'joinedAt': now,
        'createdAt': now,
        'createdBy': 'partner',
        'updatedAt': now,
        'updatedBy': 'partner',
        'schemaVersion': 1,
      });
      expect(docs.docs['users/partner'], {
        'householdId': 'h1',
        'displayName': 'Sam',
        'locale': 'en',
      });
      final invite = docs.docs['invites/${inviteCodeHash(code)}']!;
      expect(invite['usedBy'], 'partner');
      expect(invite['usedAt'], now);
    });

    test('the code may be typed in any case, with dashes or spaces', () async {
      final typed =
          '${code.substring(0, 5).toLowerCase()}- ${code.substring(5)}';
      final joined = await service.join(
        uid: 'partner',
        code: typed,
        displayName: 'Sam',
      );
      expect(joined.hid, 'h1');
    });

    test('is single use', () async {
      await service.join(uid: 'partner', code: code, displayName: 'Sam');
      // Make room again, so only the used invite can refuse.
      docs.docs['households/h1']!['memberIds'] = ['owner'];
      await expectLater(
        service.join(uid: 'third', code: code, displayName: 'Kim'),
        refusedWith(HouseholdFailure.inviteUsed),
      );
    });

    test('a third member is refused', () async {
      docs.docs['households/h1']!['memberIds'] = ['owner', 'partner'];
      await expectLater(
        service.join(uid: 'third', code: code, displayName: 'Kim'),
        refusedWith(HouseholdFailure.householdFull),
      );
      expect(docs.docs['households/h1']!['memberIds'], ['owner', 'partner']);
      expect(docs.docs['households/h1/members/third'], isNull);
      expect(docs.docs['users/third'], isNull);
    });

    test('expires after 7 days', () async {
      now = now.add(const Duration(days: 7));
      await expectLater(
        service.join(uid: 'partner', code: code, displayName: 'Sam'),
        refusedWith(HouseholdFailure.inviteExpired),
      );
      now = now.subtract(const Duration(seconds: 1));
      await service.join(uid: 'partner', code: code, displayName: 'Sam');
    });

    test('an unknown, malformed or revoked code is invite_invalid', () async {
      for (final guess in ['0000000000', 'nope', '', 'AB3DE7GH9U']) {
        await expectLater(
          service.join(uid: 'partner', code: guess, displayName: 'Sam'),
          refusedWith(HouseholdFailure.inviteInvalid),
          reason: guess,
        );
      }
      final newer = await service.createInvite(uid: 'owner', hid: 'h1');
      await expectLater(
        service.join(uid: 'partner', code: code, displayName: 'Sam'),
        refusedWith(HouseholdFailure.inviteInvalid),
      );
      await service.join(uid: 'partner', code: newer.code, displayName: 'Sam');
    });

    test('an invite whose household is gone is invite_invalid', () async {
      docs.docs.remove('households/h1');
      await expectLater(
        service.join(uid: 'partner', code: code, displayName: 'Sam'),
        refusedWith(HouseholdFailure.inviteInvalid),
      );
    });

    test('a member of another household is refused', () async {
      docs.seedMember(uid: 'partner', hid: 'h2');
      await expectLater(
        service.join(uid: 'partner', code: code, displayName: 'Sam'),
        refusedWith(HouseholdFailure.alreadyInHousehold),
      );
      expect(docs.docs['households/h1']!['memberIds'], ['owner']);
    });

    test('a stale householdId pointer does not block joining', () async {
      docs.docs['users/partner'] = {'householdId': 'gone', 'locale': 'en'};
      await service.join(uid: 'partner', code: code, displayName: 'Sam');
      expect(docs.docs['users/partner'], {
        'householdId': 'h1',
        'displayName': 'Sam',
        'locale': 'en',
      });
    });

    test('a retry by the new member succeeds and writes nothing', () async {
      await service.join(uid: 'partner', code: code, displayName: 'Sam');
      String snapshot() => {
        for (final MapEntry(:key, :value) in docs.docs.entries)
          if (key != RateLimiter.pathFor('partner')) key: value,
      }.toString();
      final before = snapshot();
      now = now.add(const Duration(minutes: 5));
      final again = await service.join(
        uid: 'partner',
        code: code,
        displayName: 'Sam',
      );
      expect(again.hid, 'h1');
      // Only the rate limiter's counter moved.
      expect(snapshot(), before);
    });

    test('display names are trimmed and checked', () async {
      for (final bad in ['', '   ', 'x' * 41, 'Sam\u0000']) {
        await expectLater(
          service.join(uid: 'partner', code: code, displayName: bad),
          refusedWith(HouseholdFailure.invalidName),
          reason: bad,
        );
      }
      expect(HouseholdService.cleanDisplayName(' Sam   Lee '), 'Sam Lee');
      expect(HouseholdService.cleanDisplayName('x' * 40), 'x' * 40);
      expect(HouseholdService.initialOf('élise'), 'É');
    });

    test('at most 10 attempts an hour per user, right or wrong', () async {
      for (var i = 0; i < 10; i++) {
        await expectLater(
          service.join(uid: 'guesser', code: 'ZZZZZZZZZZ', displayName: 'X'),
          refusedWith(HouseholdFailure.inviteInvalid),
        );
      }
      // Even the right code is refused now.
      await expectLater(
        service.join(uid: 'guesser', code: code, displayName: 'X'),
        refusedWith(HouseholdFailure.rateLimited),
      );
      // Other users are not affected.
      await service.join(uid: 'partner', code: code, displayName: 'Sam');
      now = now.add(const Duration(hours: 1));
      docs.docs['households/h1']!['memberIds'] = ['owner'];
      await expectLater(
        service.join(uid: 'guesser', code: 'ZZZZZZZZZZ', displayName: 'X'),
        refusedWith(HouseholdFailure.inviteInvalid),
      );
    });

    test('two people with the same code: exactly one gets in', () async {
      final results = await Future.wait([
        for (final uid in ['a', 'b'])
          service
              .join(uid: uid, code: code, displayName: uid)
              .then<Object>((j) => j.hid, onError: (Object e) => e),
      ]);
      expect(results.whereType<String>(), ['h1']);
      expect(results.whereType<HouseholdRejection>(), hasLength(1));
      expect(docs.docs['households/h1']!['memberIds'], hasLength(2));
    });

    test('a Firestore failure surfaces as GatewayUnavailable', () async {
      docs.failingPaths.add('invites/${inviteCodeHash(code)}');
      await expectLater(
        service.join(uid: 'partner', code: code, displayName: 'Sam'),
        throwsA(isA<GatewayUnavailable>()),
      );
    });
  });
}
