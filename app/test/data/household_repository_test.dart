import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/auth_repository_fake.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_fake.dart';
import 'package:xpense_app/data/household_repository_firebase.dart';
import 'package:xpense_shared/xpense_shared.dart';

void main() {
  group('householdFailureFromServerCode', () {
    // Every code the server's household flows and context provider send
    // (server/lib/household/household_failure.dart, auth/auth_failure.dart).
    const cases = <String, HouseholdFailure>{
      'invite_invalid': InviteInvalid(),
      'invite_expired': InviteExpired(),
      'invite_used': InviteUsed(),
      'household_full': HouseholdFull(),
      'already_in_household': AlreadyInHousehold(),
      'rate_limited': HouseholdRateLimited(),
      'household_unavailable': HouseholdServiceUnavailable(),
      'auth_unavailable': HouseholdServiceUnavailable(),
      'missing_id_token': HouseholdNotAllowed(),
      'invalid_id_token': HouseholdNotAllowed(),
      'missing_app_check': HouseholdNotAllowed(),
      'invalid_app_check': HouseholdNotAllowed(),
      'no_household': HouseholdNotAllowed(),
      'not_member': HouseholdNotAllowed(),
      'invalid_name': HouseholdUnknown('invalid_name'),
      'http_502': HouseholdUnknown('http_502'),
    };
    for (final MapEntry(key: code, value: failure) in cases.entries) {
      test('$code -> ${failure.code}', () {
        expect(householdFailureFromServerCode(code), failure);
      });
    }

    test('every failure has a stable, distinct code', () {
      final codes = {
        for (final failure in [
          const HouseholdOffline(),
          const InviteInvalid(),
          const InviteExpired(),
          const InviteUsed(),
          const HouseholdFull(),
          const AlreadyInHousehold(),
          const HouseholdRateLimited(),
          const HouseholdNotAllowed(),
          const HouseholdServiceUnavailable(),
          const HouseholdUnknown('x'),
        ])
          failure.code,
      };
      expect(codes, hasLength(10));
      expect(codes.every((c) => c.startsWith('household.')), isTrue);
    });
  });

  test('invite codes show as two groups of five', () {
    expect(formatInviteCode('AB3DE7GH9K'), 'AB3DE-7GH9K');
    expect(formatInviteCode('SHORT'), 'SHORT');
    expect(formatInviteCode(''), '');
    final invite = HouseholdInvite(
      code: 'AB3DE7GH9K',
      link: 'xpense://join?code=AB3DE7GH9K',
      expiresAt: DateTime.utc(2026, 11, 29),
    );
    expect(invite.displayCode, 'AB3DE-7GH9K');
    expect(invite.toString(), isNot(contains('AB3DE')));
  });

  group('uuidV7', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('is version 7, variant 10, with the time in front', () {
      final at = DateTime.utc(2026, 11, 22, 9);
      final id = uuidV7(at, Random(1));
      expect(id, matches(pattern));
      final ms = int.parse(id.replaceAll('-', '').substring(0, 12), radix: 16);
      expect(ms, at.millisecondsSinceEpoch);
    });

    test('later ids sort after earlier ones', () {
      final random = Random(2);
      final start = DateTime.utc(2026, 11, 22);
      final ids = [
        for (var i = 0; i < 50; i++)
          uuidV7(start.add(Duration(milliseconds: i)), random),
      ];
      expect([...ids]..sort(), ids);
      expect(ids.toSet(), hasLength(50));
    });
  });

  test('the avatar letter is the first character, upper-cased', () {
    expect(initialOf('sam'), 'S');
    expect(initialOf('élise'), 'É');
    expect(initialOf(''), '');
  });

  group('FakeHouseholdRepository', () {
    test('follows sign-in: unknown when out, onSignIn when in', () async {
      final auth = FakeAuthRepository();
      final households = FakeHouseholdRepository(auth: auth);
      addTearDown(households.dispose);
      final seen = <Membership>[];
      households.watchMembership().listen(seen.add);
      await pumpEventQueue();

      await auth.signInWithApple();
      await pumpEventQueue();
      expect(households.current, const NoHousehold());

      final created = await households.create(
        name: 'Our home',
        displayName: 'Alex',
        baseCurrency: Currency.iqd,
      );
      expect(created, const Ok<String, HouseholdFailure>('fake-new-household'));
      expect(households.current, isA<InHousehold>());

      await auth.signOut();
      await pumpEventQueue();
      expect(households.current, const MembershipUnknown());
      expect(seen.map((m) => m.runtimeType), [
        MembershipUnknown,
        NoHousehold,
        InHousehold,
        MembershipUnknown,
      ]);
    });

    test('join accepts the code in any case and with the dash', () async {
      final households = FakeHouseholdRepository(
        membership: const NoHousehold(),
      );
      expect(
        await households.join(code: 'ab3de-7gh9k', displayName: 'Sam'),
        const Ok<JoinedHousehold, HouseholdFailure>(
          FakeHouseholdRepository.partnerHousehold,
        ),
      );
      expect(
        await households.join(code: 'ZZZZZZZZZZ', displayName: 'Sam'),
        const Err<JoinedHousehold, HouseholdFailure>(InviteInvalid()),
      );
    });

    test('failNext fails only the named call', () async {
      final households = FakeHouseholdRepository(
        membership: const NoHousehold(),
      );
      households.failNext['createInvite'] = const HouseholdOffline();
      final created = await households.create(
        name: 'Our home',
        displayName: 'Alex',
        baseCurrency: Currency.usd,
      );
      expect(created, isA<Ok<String, HouseholdFailure>>());
      expect(
        await households.createInvite(),
        const Err<HouseholdInvite, HouseholdFailure>(HouseholdOffline()),
      );
      expect(
        await households.createInvite(),
        isA<Ok<HouseholdInvite, HouseholdFailure>>(),
      );
    });
  });
}
