import 'package:clock/clock.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit/io.dart';
import 'package:test/test.dart';
import 'package:xpense_agent/auth/auth_failure.dart';
import 'package:xpense_agent/auth/context_provider.dart';
import 'package:xpense_agent/auth/member_directory.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';

import '../support/fakes.dart';

void main() {
  late FakeDocumentStore docs;
  late FakeIdTokenVerifier idTokens;
  late FakeAppCheckVerifier appCheck;
  late DateTime now;
  late XpenseContextProvider provider;

  setUp(() {
    docs = FakeDocumentStore()..seedMember(uid: 'u1', hid: 'h1');
    idTokens = FakeIdTokenVerifier();
    appCheck = FakeAppCheckVerifier();
    now = DateTime.utc(2026, 11, 22, 10);
    final clock = Clock(() => now);
    provider = XpenseContextProvider(
      gateway: fakeGateway(
        documents: docs,
        idTokens: idTokens,
        appCheck: appCheck,
      ),
      members: MemberDirectory(docs, clock: clock),
      config: RuntimeConfigLoader(docs, clock: clock),
      usage: UsageCounters(docs, clock: clock),
    );
  });

  /// Expects [call] to be refused with [failure]'s status and code.
  Future<void> expectRefused(Future<Object?> call, AuthFailure failure) async {
    await expectLater(
      call,
      throwsA(
        isA<GenkitException>()
            .having((e) => e.status, 'status', failure.status)
            .having((e) => e.message, 'message', failure.code),
      ),
    );
  }

  group('success', () {
    test('returns exactly {uid, hid, locale, privacyMode, tz}', () async {
      final context = await provider.resolve(headersFor('u1'));
      expect(context, {
        'uid': 'u1',
        'hid': 'h1',
        'locale': 'en',
        'privacyMode': 'smart',
        'tz': 'Asia/Baghdad',
      });
    });

    test('verifies both tokens', () async {
      await provider.resolve(headersFor('u1'));
      expect(idTokens.calls, ['token-u1']);
      expect(appCheck.calls, ['app-ok']);
    });

    test(
      'Cloud mode passes; defaults fill a missing locale and zone',
      () async {
        docs.seedMember(
          uid: 'u2',
          hid: 'h2',
          privacyMode: 'cloud',
          locale: null,
          timeZone: null,
        );
        final context = await provider.resolve(headersFor('u2'));
        expect(context['privacyMode'], 'cloud');
        expect(context['locale'], MemberDirectory.defaultLocale);
        expect(context['tz'], MemberDirectory.defaultTimeZone);
      },
    );

    test('a missing privacy mode is the default, Smart', () async {
      docs.seedMember(uid: 'u3', hid: 'h3', privacyMode: null);
      final context = await provider.resolve(headersFor('u3'));
      expect(context['privacyMode'], 'smart');
    });

    test('accepts a lower-case bearer scheme and extra spaces', () async {
      final context = await provider.resolve({
        'authorization': '  bearer   token-u1 ',
        'x-firebase-appcheck': ' app-ok ',
      });
      expect(context['uid'], 'u1');
    });

    test('forRoute adapts RequestData', () async {
      final context = await provider.forRoute()(
        RequestData(method: 'POST', headers: headersFor('u1'), input: null),
      );
      expect(context['hid'], 'h1');
    });
  });

  group('401 unauthenticated', () {
    test('no Authorization header', () async {
      await expectRefused(
        provider.resolve({'x-firebase-appcheck': 'app-ok'}),
        AuthFailure.missingIdToken,
      );
      expect(idTokens.calls, isEmpty);
    });

    for (final header in ['token-u1', 'Basic token-u1', 'Bearer', 'Bearer ']) {
      test('malformed Authorization "$header"', () async {
        await expectRefused(
          provider.resolve({
            'authorization': header,
            'x-firebase-appcheck': 'app-ok',
          }),
          AuthFailure.missingIdToken,
        );
      });
    }

    test('no App Check header', () async {
      await expectRefused(
        provider.resolve({'authorization': 'Bearer token-u1'}),
        AuthFailure.missingAppCheck,
      );
      expect(idTokens.calls, isEmpty);
    });

    test('blank App Check header', () async {
      await expectRefused(
        provider.resolve(headersFor('u1', appCheck: '  ')),
        AuthFailure.missingAppCheck,
      );
    });

    test('rejected ID token', () async {
      await expectRefused(
        provider.resolve({
          'authorization': 'Bearer expired',
          'x-firebase-appcheck': 'app-ok',
        }),
        AuthFailure.invalidIdToken,
      );
      expect(docs.reads, isEmpty, reason: 'no lookup before verification');
    });

    test('rejected App Check token', () async {
      await expectRefused(
        provider.resolve(headersFor('u1', appCheck: 'forged')),
        AuthFailure.invalidAppCheck,
      );
      expect(docs.reads, isEmpty);
    });

    test('both rejected: the ID token is reported', () async {
      await expectRefused(
        provider.resolve({
          'authorization': 'Bearer expired',
          'x-firebase-appcheck': 'forged',
        }),
        AuthFailure.invalidIdToken,
      );
    });
  });

  group('403 permission denied', () {
    test('user without a household', () async {
      docs.docs['users/u9'] = {'locale': 'en'};
      await expectRefused(
        provider.resolve(headersFor('u9')),
        AuthFailure.noHousehold,
      );
    });

    test('user document missing', () async {
      await expectRefused(
        provider.resolve(headersFor('nobody')),
        AuthFailure.noHousehold,
      );
    });

    test(
      'householdId points at a household that does not list the user',
      () async {
        docs.seedMember(uid: 'u4', hid: 'h4', memberIds: ['someone-else']);
        await expectRefused(
          provider.resolve(headersFor('u4')),
          AuthFailure.notMember,
        );
      },
    );

    test('listed in memberIds but no member document', () async {
      docs.seedMember(uid: 'u5', hid: 'h5');
      docs.docs.remove('households/h5/members/u5');
      await expectRefused(
        provider.resolve(headersFor('u5')),
        AuthFailure.notMember,
      );
    });

    for (final hid in ['h1/members/u1', '../h1', 'a b', '', 42]) {
      test(
        'a malformed householdId ($hid) is refused before any read',
        () async {
          docs.docs['users/u11'] = {'householdId': hid};
          await expectRefused(
            provider.resolve(headersFor('u11')),
            hid == '' ? AuthFailure.noHousehold : AuthFailure.notMember,
          );
          expect(docs.reads, ['users/u11']);
        },
      );
    }

    test('household missing', () async {
      docs.docs['users/u6'] = {'householdId': 'gone'};
      await expectRefused(
        provider.resolve(headersFor('u6')),
        AuthFailure.notMember,
      );
    });

    test('On-device member is refused', () async {
      docs.seedMember(uid: 'u7', hid: 'h7', privacyMode: 'on_device');
      await expectRefused(
        provider.resolve(headersFor('u7')),
        AuthFailure.onDeviceMode,
      );
    });

    test('an unknown privacy mode fails closed to On-device', () async {
      docs.seedMember(uid: 'u8', hid: 'h8', privacyMode: 'paranoid');
      await expectRefused(
        provider.resolve(headersFor('u8')),
        AuthFailure.onDeviceMode,
      );
    });
  });

  group('429 daily limits', () {
    const day = 'households/h1/usage/2026-11-22';

    test('routes without meters never read usage', () async {
      docs.docs[day] = {'agentTurns': 9999};
      await provider.resolve(headersFor('u1'));
      expect(docs.readsOf(day), 0);
    });

    test('under the default limit passes', () async {
      docs.docs[day] = {'agentTurns': 149};
      final context = await provider.resolve(
        headersFor('u1'),
        meters: {UsageCounter.agentTurns},
      );
      expect(context['hid'], 'h1');
    });

    test('at the default limit (150 turns) is refused', () async {
      docs.docs[day] = {'agentTurns': 150};
      await expectRefused(
        provider.resolve(headersFor('u1'), meters: {UsageCounter.agentTurns}),
        AuthFailure.overLimit,
      );
    });

    test('limits come from config/runtime', () async {
      docs.docs['config/runtime'] = {
        'limits': {'decisions': 2},
      };
      docs.docs[day] = {'decisions': 2, 'agentTurns': 0};
      await expectRefused(
        provider.resolve(headersFor('u1'), meters: {UsageCounter.decisions}),
        AuthFailure.overLimit,
      );
      // Another counter of the same household is unaffected.
      await provider.resolve(
        headersFor('u1'),
        meters: {UsageCounter.agentTurns},
      );
    });

    test("yesterday's usage does not count", () async {
      docs.docs['households/h1/usage/2026-11-21'] = {'agentTurns': 500};
      await provider.resolve(
        headersFor('u1'),
        meters: {UsageCounter.agentTurns},
      );
    });

    test('an On-device member is refused before usage is read', () async {
      docs.seedMember(uid: 'u7', hid: 'h7', privacyMode: 'on_device');
      await expectRefused(
        provider.resolve(headersFor('u7'), meters: {UsageCounter.agentTurns}),
        AuthFailure.onDeviceMode,
      );
      expect(docs.readsOf('households/h7/usage/2026-11-22'), 0);
    });
  });

  group('503 unavailable', () {
    test('Auth backend down', () async {
      await expectRefused(
        provider.resolve({
          'authorization': 'Bearer down',
          'x-firebase-appcheck': 'app-ok',
        }),
        AuthFailure.unavailable,
      );
    });

    test('App Check backend down', () async {
      await expectRefused(
        provider.resolve(headersFor('u1', appCheck: 'down')),
        AuthFailure.unavailable,
      );
    });

    test('Firestore down during member lookup', () async {
      docs.failingPaths.add('households/h1/members/u1');
      await expectRefused(
        provider.resolve(headersFor('u1')),
        AuthFailure.unavailable,
      );
    });

    test('Firestore down while reading usage', () async {
      docs.failingPaths.add('households/h1/usage/2026-11-22');
      await expectRefused(
        provider.resolve(headersFor('u1'), meters: {UsageCounter.images}),
        AuthFailure.unavailable,
      );
    });
  });

  group('60 s member cache', () {
    test('a second request within 60 s reads no member documents', () async {
      await provider.resolve(headersFor('u1'));
      final readsAfterFirst = docs.reads.length;
      now = now.add(const Duration(seconds: 59));
      await provider.resolve(headersFor('u1'));
      expect(docs.reads.length, readsAfterFirst);
      expect(idTokens.calls, hasLength(2), reason: 'tokens are never cached');
    });

    test('a privacy change takes effect after 60 s', () async {
      await provider.resolve(headersFor('u1'));
      docs.docs['households/h1/members/u1']!['privacyMode'] = 'on_device';
      now = now.add(const Duration(seconds: 30));
      await provider.resolve(headersFor('u1'));
      now = now.add(const Duration(seconds: 31));
      await expectRefused(
        provider.resolve(headersFor('u1')),
        AuthFailure.onDeviceMode,
      );
    });

    test('refusals are not cached: joining works at once', () async {
      await expectRefused(
        provider.resolve(headersFor('u10')),
        AuthFailure.noHousehold,
      );
      docs.seedMember(uid: 'u10', hid: 'h10');
      final context = await provider.resolve(headersFor('u10'));
      expect(context['hid'], 'h10');
    });
  });
}
