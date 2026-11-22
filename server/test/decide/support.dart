// Fixtures for the /decide tests: a two-member household like WP-S4's.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/decide/household_profile.dart';
import 'package:xpense_shared/xpense_shared.dart';

const context = XpenseContext(
  uid: 'uDara',
  hid: 'h1',
  locale: 'en',
  privacyMode: PrivacyMode.smart,
  tz: 'Asia/Baghdad',
);

const cashId = 'k3Qw8ZpL1rT6yVb2nM0a';
const checkingId = 'm2Rt6YwN8qZ3vB7xL4cC';
const jointCardId = 'j7Vb3Nq9Wc2Xz5Lk8Pd1';
const alexId = 'pAlex0000000000000001';

final HouseholdProfile fixtureProfile = HouseholdProfile(
  baseCurrency: 'USD',
  members: const [
    ProfileMember(uid: 'uDara', name: 'Dara'),
    ProfileMember(uid: 'uShilan', name: 'Shilan'),
  ],
  accounts: const [
    ProfileAccount(
      id: cashId,
      name: 'Cash wallet',
      currency: 'IQD',
      kind: 'cash',
      joint: false,
      ownerUid: 'uDara',
    ),
    ProfileAccount(
      id: checkingId,
      name: 'Checking account',
      currency: 'USD',
      kind: 'bank',
      joint: false,
      ownerUid: 'uDara',
    ),
    ProfileAccount(
      id: jointCardId,
      name: 'Joint Visa card',
      currency: 'USD',
      kind: 'credit',
      joint: true,
    ),
  ],
  people: const [
    ProfilePerson(id: alexId, name: 'Alex', aliases: ['Al']),
    ProfilePerson(id: 'pShilan', name: 'Shilan', memberUid: 'uShilan'),
  ],
  categories: [
    for (final c in defaultCategories)
      ProfileCategory(
        id: c.slug,
        slug: c.slug,
        name: c.nameIn('en'),
        kind: c.kind,
        parentId: c.parentSlug,
      ),
  ],
);

/// An in-memory [HouseholdSource].
final class FakeHouseholdSource implements HouseholdSource {
  new({HouseholdProfile? profile, this.entries = const []})
    : _profile = profile ?? fixtureProfile;

  final HouseholdProfile _profile;
  List<RecentEntry> entries;
  bool failProfile = false;
  bool failEntries = false;
  final queries = <({int amountMinor, String fromDay, String toDay})>[];

  @override
  Future<HouseholdProfile> profile({
    required String hid,
    required String uid,
  }) async {
    if (failProfile) throw const GatewayUnavailable('householdProfile');
    return _profile;
  }

  @override
  Future<List<RecentEntry>> entriesWithAmount({
    required String hid,
    required String uid,
    required int amountMinor,
    required String fromDay,
    required String toDay,
  }) async {
    queries.add((amountMinor: amountMinor, fromDay: fromDay, toDay: toDay));
    if (failEntries) throw const GatewayUnavailable('entriesWithAmount');
    return [
      for (final e in entries)
        if (e.amountMinor == amountMinor &&
            e.occurredOn.compareTo(fromDay) >= 0 &&
            e.occurredOn.compareTo(toDay) <= 0)
          e,
    ];
  }
}

/// A Decisions API answer body with [answers] and [inputTokens].
String answeredBody(Map<String, Object?> answers, {int inputTokens = 2000}) =>
    jsonEncode({
      'answers': answers,
      'usage': {
        'total_tokens': inputTokens,
        'total_input_tokens': inputTokens,
        'input_tokens_by_modality': [
          {'modality': 'TEXT', 'tokens': inputTokens},
        ],
        'total_output_tokens': 0,
      },
    });

Map<String, Object?> choice(String key, double p) => {
  'type': 'choice',
  'choice': key,
  'probabilities': {key: p},
  'confidence': p,
};

Map<String, Object?> yesNo(double p) => {
  'type': 'noul',
  'noul': p,
  'confidence': p > 0.5 ? p : 1 - p,
};

/// Google's error shape (numeric code and status).
String googleError(int code, String status, String message) => jsonEncode({
  'error': {'code': code, 'message': message, 'status': status},
});

/// The Decisions API's own error shape (string code).
String decisionsError(String code, String message) => jsonEncode({
  'error': {'code': code, 'message': message},
});

/// A scripted HTTP client: answers each request with the next response in
/// [script] and records the requests.
final class ScriptedHttp {
  new(this.script);

  final List<Object> script;
  final requests = <http.Request>[];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    if (requests.length > script.length) {
      throw StateError('unexpected request ${requests.length}');
    }
    final next = script[requests.length - 1];
    return switch (next) {
      final http.Response r => r,
      final Exception e => throw e,
      _ => throw StateError('bad script entry $next'),
    };
  });

  Map<String, Object?> bodyOf(int i) =>
      jsonDecode(requests[i].body) as Map<String, Object?>;
}
