/// The admin gateway: every call the server makes with admin rights.
///
/// Auth, App Check, Firestore and Messaging sit behind the small interfaces
/// below so the rest of the server never imports `firebase_admin_sdk` or
/// `google_cloud_firestore` (ARCHITECTURE 4.3, DELEGATION rule 7). The
/// Firebase implementation is in `firebase_admin_gateway.dart`; tests use
/// fakes.
library;

import 'package:meta/meta.dart';

/// A verified Firebase ID token.
@immutable
final class VerifiedUser {
  /// Creates a verified user.
  const new({required this.uid});

  /// The Firebase Auth user id (`sub`).
  final String uid;
}

/// A verified App Check token.
@immutable
final class VerifiedApp {
  /// Creates a verified app.
  const new({required this.appId});

  /// The Firebase app id the token was issued to.
  final String appId;
}

/// A token the gateway checked and refused (expired, revoked, wrong project,
/// bad signature, disabled user). The client should get a fresh token.
final class TokenRejected implements Exception {
  /// Creates a rejection. [reason] is a short machine code from the SDK; it is
  /// logged, never sent to the client.
  const new(this.reason);

  /// SDK error code, e.g. `auth/id-token-expired`.
  final String reason;

  @override
  String toString() => 'TokenRejected($reason)';
}

/// The gateway could not reach a backend (network, quota, permissions). The
/// request may succeed later; the token itself was not judged.
final class GatewayUnavailable implements Exception {
  /// Creates the failure. [operation] names the call, [cause] is the
  /// underlying error, kept for logs.
  const new(this.operation, [this.cause]);

  /// The gateway call that failed, e.g. `verifyIdToken`.
  final String operation;

  /// The underlying error.
  final Object? cause;

  @override
  String toString() => 'GatewayUnavailable($operation): $cause';
}

/// Verifies Firebase ID tokens.
abstract interface class IdTokenVerifier {
  /// Returns the verified user, or throws [TokenRejected] or
  /// [GatewayUnavailable].
  Future<VerifiedUser> verifyIdToken(String idToken);
}

/// Verifies App Check tokens.
abstract interface class AppCheckVerifier {
  /// Returns the verified app, or throws [TokenRejected] or
  /// [GatewayUnavailable].
  Future<VerifiedApp> verifyAppCheckToken(String token);
}

/// Server-side Firestore access with admin rights (rules do not apply).
///
/// Paths are slash-separated document paths, e.g. `households/h1/usage/day`.
/// Values are plain Dart: `String`, `int`, `double`, `bool`, `null`, `List`,
/// `Map<String, Object?>` and `DateTime` (for timestamps).
abstract interface class DocumentStore {
  /// Reads one document. Returns null when it does not exist.
  Future<Map<String, Object?>?> read(String path);

  /// Atomically adds [deltas] to integer fields of the document at [path],
  /// creating the document and missing fields as needed. [fields] are set
  /// (merged) in the same write.
  Future<void> increment(
    String path,
    Map<String, int> deltas, {
    Map<String, Object?> fields = const {},
  });

  /// Writes [data] to the document at [path]; with [merge], fields not in
  /// [data] are kept.
  Future<void> write(
    String path,
    Map<String, Object?> data, {
    bool merge = false,
  });

  /// Runs [body] in one Firestore transaction and returns its result.
  ///
  /// Every read happens before the first write. The store may run [body]
  /// more than once when another writer touched the same documents, so it
  /// must have no side effects outside [DocumentTransaction]. An exception
  /// thrown by [body] rolls the transaction back and reaches the caller
  /// unchanged; a backend failure is a [GatewayUnavailable].
  Future<T> transaction<T>(Future<T> Function(DocumentTransaction tx) body);

  /// One page of the documents directly in [collection] whose [field]
  /// equals [value], ordered by document id, starting after the document id
  /// [startAfterId] when given, at most [limit] of them. Jobs page through
  /// large sets with it (WP-13 visibility backfill).
  Future<List<StoredDocument>> pageWhereEquals(
    String collection,
    String field,
    Object value, {
    int limit = 400,
    String? startAfterId,
  });

  /// How many documents directly in [collection] have [field] equal to
  /// [value] (a count aggregation; documents are not read).
  Future<int> countWhereEquals(String collection, String field, Object value);

  /// Applies [writes] in one batch: all or none. At most 500 writes.
  Future<void> writeAll(List<DocumentWrite> writes);
}

/// One write of a [DocumentStore.writeAll] batch.
@immutable
final class DocumentWrite {
  /// Writes [data] to [path]; with [merge], fields not in [data] are kept
  /// (nested maps are merged too).
  const new(this.path, this.data, {this.merge = false});

  /// The document path.
  final String path;

  /// The fields to write.
  final Map<String, Object?> data;

  /// Whether to merge into the existing document.
  final bool merge;
}

/// A document returned by a query: its slash-separated [path] and [data].
@immutable
final class StoredDocument {
  /// Creates a stored document.
  const new(this.path, this.data);

  /// The document path, e.g. `invites/abc`.
  final String path;

  /// The document's fields, in the plain Dart values of [DocumentStore].
  final Map<String, Object?> data;
}

/// Reads and writes inside one [DocumentStore.transaction].
///
/// Reads come first: the store refuses a read after a write. Writes are
/// applied together when the body returns.
abstract interface class DocumentTransaction {
  /// Reads one document. Returns null when it does not exist.
  Future<Map<String, Object?>?> read(String path);

  /// The documents directly in [collection] whose [field] equals [value], at
  /// most [limit] of them.
  Future<List<StoredDocument>> whereEquals(
    String collection,
    String field,
    Object value, {
    int limit = 50,
  });

  /// The documents directly in [collection] whose list [field] contains
  /// [value], at most [limit] of them.
  Future<List<StoredDocument>> whereArrayContains(
    String collection,
    String field,
    Object value, {
    int limit = 50,
  });

  /// Writes [data] to [path]; with [merge], fields not in [data] are kept.
  void write(String path, Map<String, Object?> data, {bool merge = false});

  /// Deletes the document at [path]. Deleting a missing document is fine.
  void delete(String path);
}

/// A push notification to one device.
@immutable
final class PushMessage {
  /// Creates a message. Push bodies carry localisation keys and ids, never
  /// amounts, names or message text (DATA_MODEL 2.14).
  const new({required this.token, this.title, this.body, this.data = const {}});

  /// The FCM registration token of the device.
  final String token;

  /// Visible title, if any.
  final String? title;

  /// Visible body, if any.
  final String? body;

  /// Data payload read by the app.
  final Map<String, String> data;
}

/// Sends push notifications through Firebase Cloud Messaging.
abstract interface class PushSender {
  /// Sends [message] and returns the FCM message id.
  Future<String> send(PushMessage message);
}

/// The admin gateway: one object holding every admin capability.
final class AdminGateway {
  /// Creates a gateway from its parts. [_onClose] releases shared resources.
  new({
    required this.idTokens,
    required this.appCheck,
    required this.documents,
    required this.push,
    this._onClose,
  });

  /// Firebase ID token verification.
  final IdTokenVerifier idTokens;

  /// App Check token verification.
  final AppCheckVerifier appCheck;

  /// Firestore with admin rights.
  final DocumentStore documents;

  /// Firebase Cloud Messaging.
  final PushSender push;

  final Future<void> Function()? _onClose;

  /// Releases connections. The gateway cannot be used afterwards.
  Future<void> close() async {
    await _onClose?.call();
  }
}
