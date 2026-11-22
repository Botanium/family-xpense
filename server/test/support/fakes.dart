// Test doubles for the admin gateway.
import 'dart:async';

import 'package:xpense_agent/admin/admin_gateway.dart';

/// A transaction over [FakeDocumentStore]: reads see the committed
/// documents, writes are buffered and applied when the body returns, and a
/// read after a write is refused, as in Firestore.
final class _FakeTransaction implements DocumentTransaction {
  new(this._store);

  final FakeDocumentStore _store;
  final _writes = <void Function()>[];

  void _checkReadable() {
    if (_writes.isNotEmpty) {
      throw StateError('Firestore transactions read before they write');
    }
  }

  @override
  Future<Map<String, Object?>?> read(String path) {
    _checkReadable();
    return _store.read(path);
  }

  @override
  Future<List<StoredDocument>> whereEquals(
    String collection,
    String field,
    Object value, {
    int limit = 50,
  }) async {
    _checkReadable();
    final depth = collection.split('/').length + 1;
    return [
      for (final MapEntry(key: path, value: data) in _store.docs.entries)
        if (path.startsWith('$collection/') &&
            path.split('/').length == depth &&
            data[field] == value)
          StoredDocument(path, Map.of(data)),
    ].take(limit).toList();
  }

  @override
  void write(String path, Map<String, Object?> data, {bool merge = false}) =>
      _writes.add(() => unawaited(_store.write(path, data, merge: merge)));

  @override
  void delete(String path) => _writes.add(() => _store.docs.remove(path));

  void _apply() {
    for (final write in _writes) {
      write();
    }
  }
}

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

  /// Transactions run one at a time, like Firestore's serialisable ones.
  Future<void> _lock = Future.value();

  /// Number of transactions that committed.
  int commits = 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function(DocumentTransaction tx) body,
  ) async {
    final previous = _lock;
    final done = Completer<void>();
    _lock = done.future;
    await previous;
    try {
      final tx = _FakeTransaction(this);
      final result = await body(tx);
      tx._apply();
      commits++;
      return result;
    } finally {
      done.complete();
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
