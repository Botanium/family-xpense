// Test doubles for the admin gateway.
import 'package:xpense_agent/admin/admin_gateway.dart';

/// In-memory documents keyed by path.
final class FakeDocumentStore implements DocumentStore {
  final docs = <String, Map<String, Object?>>{};
  final reads = <String>[];
  final failingPaths = <String>{};

  /// Number of reads of [path].
  int readsOf(String path) => reads.where((p) => p == path).length;

  @override
  Future<Map<String, Object?>?> read(String path) async {
    reads.add(path);
    if (failingPaths.contains(path)) {
      throw GatewayUnavailable('read', 'injected failure for $path');
    }
    final doc = docs[path];
    return doc == null ? null : Map.of(doc);
  }

  @override
  Future<void> increment(
    String path,
    Map<String, int> deltas, {
    Map<String, Object?> fields = const {},
  }) async {
    final doc = docs.putIfAbsent(path, () => {})..addAll(fields);
    for (final MapEntry(:key, :value) in deltas.entries) {
      doc[key] = ((doc[key] as int?) ?? 0) + value;
    }
  }

  @override
  Future<void> write(
    String path,
    Map<String, Object?> data, {
    bool merge = false,
  }) async {
    if (merge) {
      docs.putIfAbsent(path, () => {}).addAll(data);
    } else {
      docs[path] = Map.of(data);
    }
  }

  /// Seeds a household with one member, as the founding batch writes it.
  void seedMember({
    required String uid,
    required String hid,
    String? privacyMode = 'smart',
    String? locale = 'en',
    String? timeZone = 'Asia/Baghdad',
    List<String>? memberIds,
  }) {
    docs['users/$uid'] = {'householdId': hid, 'locale': ?locale};
    docs['households/$hid'] = {
      'memberIds': memberIds ?? [uid],
      'timeZone': ?timeZone,
    };
    docs['households/$hid/members/$uid'] = {
      'role': 'owner',
      'privacyMode': ?privacyMode,
    };
  }
}

/// ID tokens: `token-<uid>` verifies as `<uid>`; `expired` is rejected;
/// `down` makes the backend unavailable.
final class FakeIdTokenVerifier implements IdTokenVerifier {
  final calls = <String>[];

  @override
  Future<VerifiedUser> verifyIdToken(String idToken) async {
    calls.add(idToken);
    if (idToken == 'down') throw const GatewayUnavailable('verifyIdToken');
    if (idToken.startsWith('token-')) {
      return VerifiedUser(uid: idToken.substring('token-'.length));
    }
    throw const TokenRejected('auth/id-token-expired');
  }
}

/// App Check: `app-ok` verifies; `down` makes the backend unavailable;
/// anything else is rejected.
final class FakeAppCheckVerifier implements AppCheckVerifier {
  final calls = <String>[];

  @override
  Future<VerifiedApp> verifyAppCheckToken(String token) async {
    calls.add(token);
    if (token == 'down') throw const GatewayUnavailable('verifyAppCheckToken');
    if (token == 'app-ok') return const VerifiedApp(appId: '1:ios:test');
    throw const TokenRejected('appCheck/invalid-argument');
  }
}

final class FakePushSender implements PushSender {
  final sent = <PushMessage>[];

  @override
  Future<String> send(PushMessage message) async {
    sent.add(message);
    return 'msg-${sent.length}';
  }
}

/// A gateway made of fakes.
AdminGateway fakeGateway({
  FakeDocumentStore? documents,
  IdTokenVerifier? idTokens,
  AppCheckVerifier? appCheck,
}) => AdminGateway(
  idTokens: idTokens ?? FakeIdTokenVerifier(),
  appCheck: appCheck ?? FakeAppCheckVerifier(),
  documents: documents ?? FakeDocumentStore(),
  push: FakePushSender(),
);

/// Valid request headers for [uid].
Map<String, String> headersFor(String uid, {String appCheck = 'app-ok'}) => {
  'authorization': 'Bearer token-$uid',
  'x-firebase-appcheck': appCheck,
};
