/// The [AdminGateway] over `firebase_admin_sdk` 0.5.6 (D-06).
///
/// The only file that imports `firebase_admin_sdk`. Firestore is the
/// `google_cloud_firestore` client that the SDK returns from `app.firestore()`.
///
/// Emulators: the SDK reads `FIREBASE_AUTH_EMULATOR_HOST` and
/// `FIRESTORE_EMULATOR_HOST` itself. With the Auth emulator, `verifyIdToken`
/// accepts the emulator's unsigned tokens and checks the user record on every
/// call. App Check has no emulator; pass a verifier as
/// `appCheckOverride`.
library;

import 'dart:async';

import 'package:firebase_admin_sdk/app_check.dart' as app_check;
import 'package:firebase_admin_sdk/auth.dart' as auth;
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:firebase_admin_sdk/messaging.dart' as fcm;
import 'package:google_cloud_firestore/google_cloud_firestore.dart' as fs;

import 'package:xpense_agent/admin/admin_gateway.dart';

/// The Firebase-backed admin gateway, plus the raw Firestore client that the
/// agent runtime needs for `FirestoreSessionStore` (D-11, D-31).
final class FirebaseAdminGateway {
  new _(this._app, this.gateway);

  /// Initialises a named Firebase app for [projectId] and builds the gateway.
  ///
  /// Credentials come from Application Default Credentials (the Cloud Run
  /// service account) when a backend that needs them is first used; the
  /// emulators need none. [appCheckOverride] replaces App Check verification
  /// (tests and local emulator runs only; `ServerEnv` refuses it on Cloud
  /// Run).
  factory initialize({
    required String projectId,
    AppCheckVerifier? appCheckOverride,
    String appName = 'xpense-agent',
  }) {
    final app = FirebaseApp.initializeApp(
      name: appName,
      options: AppOptions(projectId: projectId),
    );
    final gateway = AdminGateway(
      idTokens: _FirebaseIdTokenVerifier(app.auth()),
      appCheck: appCheckOverride ?? _FirebaseAppCheckVerifier(app.appCheck()),
      documents: _FirestoreDocumentStore(app.firestore()),
      push: _FcmPushSender(app.messaging()),
      onClose: app.close,
    );
    return FirebaseAdminGateway._(app, gateway);
  }

  final FirebaseApp _app;

  /// The gateway the rest of the server uses.
  final AdminGateway gateway;

  /// The Firestore client, for `lib/runtime/` only (session store).
  fs.Firestore get firestore => _app.firestore();
}

/// Auth error codes that mean "this token is not acceptable", as opposed to
/// "the check could not be made".
const Set<auth.AuthClientErrorCode> _rejectedAuthCodes = {
  auth.AuthClientErrorCode.invalidArgument,
  auth.AuthClientErrorCode.invalidIdToken,
  auth.AuthClientErrorCode.idTokenExpired,
  auth.AuthClientErrorCode.idTokenRevoked,
  auth.AuthClientErrorCode.userDisabled,
  auth.AuthClientErrorCode.userNotFound,
};

final class _FirebaseIdTokenVerifier implements IdTokenVerifier {
  new(this._auth);

  final auth.Auth _auth;

  @override
  Future<VerifiedUser> verifyIdToken(String idToken) async {
    try {
      // checkRevoked: a disabled or signed-out user is refused at once, at the
      // cost of one Auth lookup per request; the member cache does not cover
      // it because revocation must not wait 60 s.
      final decoded = await _auth.verifyIdToken(idToken, checkRevoked: true);
      return VerifiedUser(uid: decoded.uid);
    } on auth.FirebaseAuthAdminException catch (e) {
      if (_rejectedAuthCodes.contains(e.errorCode)) {
        throw TokenRejected(e.code);
      }
      throw GatewayUnavailable('verifyIdToken', e.code);
    } on Exception catch (e) {
      throw GatewayUnavailable('verifyIdToken', e.runtimeType);
    }
  }
}

final class _FirebaseAppCheckVerifier implements AppCheckVerifier {
  new(this._appCheck);

  final app_check.AppCheck _appCheck;

  static const Set<app_check.AppCheckErrorCode> _unavailableCodes = {
    app_check.AppCheckErrorCode.internalError,
    app_check.AppCheckErrorCode.invalidCredential,
    app_check.AppCheckErrorCode.unknownError,
  };

  @override
  Future<VerifiedApp> verifyAppCheckToken(String token) async {
    try {
      final result = await _appCheck.verifyToken(token);
      return VerifiedApp(appId: result.appId);
    } on app_check.FirebaseAppCheckException catch (e) {
      if (_unavailableCodes.any((c) => e.code.endsWith(c.code))) {
        throw GatewayUnavailable('verifyAppCheckToken', e.code);
      }
      throw TokenRejected(e.code);
    } on Exception catch (e) {
      throw GatewayUnavailable('verifyAppCheckToken', e.runtimeType);
    }
  }
}

final class _FirestoreDocumentStore implements DocumentStore {
  new(this._db);

  final fs.Firestore _db;

  @override
  Future<Map<String, Object?>?> read(String path) async {
    try {
      final snapshot = await _db.doc(path).get();
      final data = snapshot.data();
      return data == null
          ? null
          : _fromFirestore(data)! as Map<String, Object?>;
    } on Exception catch (e) {
      throw GatewayUnavailable('read', e);
    }
  }

  @override
  Future<void> increment(
    String path,
    Map<String, int> deltas, {
    Map<String, Object?> fields = const {},
  }) async {
    try {
      await _db.doc(path).set({
        ...fields,
        for (final MapEntry(:key, :value) in deltas.entries)
          key: fs.FieldValue.increment(value),
      }, options: const fs.SetOptions.merge());
    } on Exception catch (e) {
      throw GatewayUnavailable('increment', e);
    }
  }

  @override
  Future<void> write(
    String path,
    Map<String, Object?> data, {
    bool merge = false,
  }) async {
    try {
      await _db
          .doc(path)
          .set(data, options: merge ? const fs.SetOptions.merge() : null);
    } on Exception catch (e) {
      throw GatewayUnavailable('write', e);
    }
  }
}

/// Converts Firestore values to plain Dart (timestamps become UTC DateTimes).
Object? _fromFirestore(Object? value) => switch (value) {
  fs.Timestamp() => value.toDate(),
  Map<Object?, Object?>() => {
    for (final MapEntry(:key, :value) in value.entries)
      key.toString(): _fromFirestore(value),
  },
  List<Object?>() => [for (final v in value) _fromFirestore(v)],
  _ => value,
};

final class _FcmPushSender implements PushSender {
  new(this._messaging);

  final fcm.Messaging _messaging;

  @override
  Future<String> send(PushMessage message) {
    final hasNotification = message.title != null || message.body != null;
    return _messaging.send(
      fcm.TokenMessage(
        token: message.token,
        data: message.data.isEmpty ? null : message.data,
        notification: hasNotification
            ? fcm.Notification(title: message.title, body: message.body)
            : null,
      ),
    );
  }
}
