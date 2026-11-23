import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/read/home_reader_firebase.dart';
import 'package:xpense_app/data/read/scoped_listen.dart';

/// The refusal Firestore gives a listener before the server knows the new
/// member (Codex review, PR #37).
final FirebaseException denied = FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
);

/// A `build` whose listens fail with [failures] in turn, then emit the
/// scope's name; it records every listen.
class FakeQuery {
  new(this.failures);

  final List<Object> failures;
  final List<String> listens = [];

  Stream<String> call(String scope) {
    listens.add(scope);
    if (failures.isNotEmpty) {
      return Stream<String>.error(failures.removeAt(0));
    }
    return Stream<String>.value('rows of $scope');
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  late StreamController<String?> scopes;
  late List<String> values;
  late List<Object> errors;
  late StreamSubscription<String> sub;

  void listen(FakeQuery query, {int retries = 3}) {
    sub = scopedListen<String, String>(
      scopes: scopes.stream,
      build: query.call,
      empty: 'empty',
      isTransient: isTransientDenial,
      retries: retries,
      retryDelay: const Duration(milliseconds: 1),
    ).listen(values.add, onError: errors.add);
  }

  setUp(() {
    scopes = StreamController<String?>();
    values = [];
    errors = [];
  });

  tearDown(() async {
    await sub.cancel();
    await scopes.close();
  });

  test(
    'a denial right after joining is retried; the rows then arrive',
    () async {
      final query = FakeQuery([denied, denied]);
      listen(query);

      scopes.add('home');
      await settle();

      expect(values, ['rows of home']);
      expect(errors, isEmpty);
      expect(query.listens, ['home', 'home', 'home']);
    },
  );

  test('gives up after the last retry and passes the denial on', () async {
    final query = FakeQuery([denied, denied, denied, denied, denied]);
    listen(query, retries: 2);

    scopes.add('home');
    await settle();

    expect(values, isEmpty);
    expect(errors, [denied]);
    expect(query.listens, hasLength(3));
  });

  test('other errors are not retried', () async {
    final other = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'internal',
    );
    final query = FakeQuery([other]);
    listen(query);

    scopes.add('home');
    await settle();

    expect(errors, [other]);
    expect(query.listens, ['home']);
  });

  test('a scope change while waiting drops the stale retry', () async {
    final query = FakeQuery([denied]);
    sub = scopedListen<String, String>(
      scopes: scopes.stream,
      build: query.call,
      empty: 'empty',
      isTransient: isTransientDenial,
      retryDelay: const Duration(milliseconds: 30),
    ).listen(values.add, onError: errors.add);

    scopes.add('first');
    await Future<void>.delayed(Duration.zero);
    scopes.add('second');
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(values, ['rows of second']);
    expect(query.listens, ['first', 'second']);
  });

  test('no scope emits empty; the same scope again does not restart', () async {
    final query = FakeQuery([]);
    listen(query);

    scopes
      ..add(null)
      ..add('home')
      ..add('home');
    await settle();

    expect(values, ['empty', 'rows of home']);
    expect(query.listens, ['home']);
  });
}
