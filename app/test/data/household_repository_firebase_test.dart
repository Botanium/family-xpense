// The Firebase adapter's server calls without a usable server address
// (PR #29 review): an unset or malformed XPENSE_SERVER_URL must read as
// "unavailable", never reach HttpClient as a relative URL.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/data/household_repository_firebase.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A signed-in user whose ID token is always ready.
final class _User implements User {
  @override
  String get uid => 'u1';

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'token';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Firebase Auth with [_User] signed in and no state changes.
final class _Auth implements FirebaseAuth {
  @override
  User? get currentUser => _User();

  @override
  Stream<User?> authStateChanges() => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Firestore is not touched by the server calls.
final class _Firestore implements FirebaseFirestore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FirebaseHouseholdRepository repositoryWith(Uri? serverUrl) =>
    FirebaseHouseholdRepository(
      auth: _Auth(),
      firestore: _Firestore(),
      appCheckToken: () async => 'app-check',
      serverUrl: serverUrl,
    );

void main() {
  group('usableServerUrl', () {
    test('accepts absolute http and https addresses', () {
      expect(
        usableServerUrl('https://xpense-agent-abc.run.app'),
        Uri.parse('https://xpense-agent-abc.run.app'),
      );
      expect(
        usableServerUrl(' http://127.0.0.1:8080/ '),
        Uri.parse('http://127.0.0.1:8080/'),
      );
    });

    test('refuses unset, relative and other schemes', () {
      for (final raw in [
        null,
        '',
        '   ',
        'example.com',
        '/v1',
        'ftp://example.com',
        'xpense://join',
        'https://',
        'http://[',
      ]) {
        expect(usableServerUrl(raw), isNull, reason: '$raw');
      }
    });
  });

  group('without a usable server address', () {
    for (final (name, url) in [
      ('unset', null),
      // What `Uri.tryParse('')` gives for an empty --dart-define.
      ('empty', Uri.parse('')),
      ('relative', Uri.parse('example.com')),
      ('another scheme', Uri.parse('ftp://example.com')),
    ]) {
      test('$name: invites and joins say the server is unavailable', () async {
        final repository = repositoryWith(url);
        expect(
          await repository.createInvite(),
          const Err<HouseholdInvite, HouseholdFailure>(
            HouseholdServiceUnavailable(),
          ),
        );
        expect(
          await repository.join(code: 'AB3DE7GH9K', displayName: 'Sam'),
          const Err<JoinedHousehold, HouseholdFailure>(
            HouseholdServiceUnavailable(),
          ),
        );
      });
    }
  });
}
