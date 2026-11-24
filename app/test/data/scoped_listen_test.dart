import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
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
  StreamSubscription<String>? sub;

  void listen(
    FakeQuery query, {
    int retries = 3,
    Duration retryDelay = const Duration(milliseconds: 1),
    bool emptyWhileRetrying = false,
  }) {
    sub = scopedListen<String, String>(
      scopes: scopes.stream,
      build: query.call,
      empty: 'empty',
      retries: retries,
      retryDelay: retryDelay,
      emptyWhileRetrying: emptyWhileRetrying,
    ).listen(values.add, onError: errors.add);
  }

  setUp(() {
    scopes = StreamController<String?>();
    values = [];
    errors = [];
  });

  tearDown(() async {
    await sub?.cancel();
    sub = null;
    // No listener is left to take the done event, so do not wait for it.
    unawaited(scopes.close());
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

  test('emptyWhileRetrying reads empty while a retry waits', () async {
    final query = FakeQuery([denied, denied]);
    listen(query, emptyWhileRetrying: true);

    scopes.add('home');
    await settle();

    expect(values, ['empty', 'empty', 'rows of home']);
    expect(errors, isEmpty);
  });

  test('the wait doubles from the first delay', () async {
    final starts = <DateTime>[];
    final failures = <Object>[denied, denied, denied];
    sub = scopedListen<String, String>(
      scopes: scopes.stream,
      build: (scope) {
        starts.add(DateTime.now());
        return failures.isEmpty
            ? Stream.value('rows')
            : Stream.error(failures.removeAt(0));
      },
      empty: 'empty',
      retryDelay: const Duration(milliseconds: 20),
    ).listen(values.add, onError: errors.add);

    scopes.add('home');
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(values, ['rows']);
    expect(starts, hasLength(4));
    final gaps = [
      for (var i = 1; i < starts.length; i++)
        starts[i].difference(starts[i - 1]).inMilliseconds,
    ];
    // 20, 40, 80 ms: each at least its own delay.
    expect(gaps[0], greaterThanOrEqualTo(20));
    expect(gaps[1], greaterThanOrEqualTo(40));
    expect(gaps[2], greaterThanOrEqualTo(80));
  });

  test('gives up after the last retry and passes the denial on', () async {
    final query = FakeQuery([denied, denied, denied, denied, denied]);
    listen(query, retries: 2);

    scopes.add('home');
    await settle();

    expect(values, isEmpty);
    expect(errors, [denied]);
    expect(query.listens, hasLength(3));
  });

  test('a success resets the retry count', () async {
    final events = StreamController<String>.broadcast();
    var listens = 0;
    sub = scopedListen<String, String>(
      scopes: scopes.stream,
      build: (_) {
        listens++;
        return events.stream;
      },
      empty: 'empty',
      retries: 1,
      retryDelay: const Duration(milliseconds: 1),
    ).listen(values.add, onError: errors.add);
    scopes.add('home');
    await settle();

    // Refused, retried, then a value: the one retry is available again.
    events.addError(denied);
    await settle();
    events.add('rows');
    await settle();
    events.addError(denied);
    await settle();

    expect(listens, 3);
    expect(values, ['rows']);
    expect(errors, isEmpty);
    await events.close();
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

  test('errors that are not Firebase ones are passed on', () async {
    final query = FakeQuery([StateError('boom')]);
    listen(query);

    scopes.add('home');
    await settle();

    expect(errors.single, isA<StateError>());
    expect(query.listens, ['home']);
  });

  test('after an error ends it, the same scope listens anew', () async {
    final query = FakeQuery([denied, denied]);
    listen(query, retries: 1);

    scopes.add('home');
    await settle();
    expect(errors, [denied]);
    expect(query.listens, ['home', 'home']);

    scopes.add('home');
    await settle();
    expect(query.listens, ['home', 'home', 'home']);
    expect(values, ['rows of home']);
  });

  test('the same scope is ignored while a retry waits', () async {
    final query = FakeQuery([denied]);
    listen(query, retryDelay: const Duration(milliseconds: 20));

    scopes.add('home');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    scopes.add('home');
    await settle();

    expect(query.listens, ['home', 'home']);
    expect(values, ['rows of home']);
  });

  test('a scope change while waiting drops the stale retry', () async {
    final query = FakeQuery([denied]);
    listen(query, retryDelay: const Duration(milliseconds: 30));

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
      ..add(null)
      ..add('home')
      ..add('home');
    await settle();

    expect(values, ['empty', 'rows of home']);
    expect(query.listens, ['home']);
  });

  test('leaving the household cancels the listener and reads empty', () async {
    var cancelled = false;
    sub = scopedListen<String, String>(
      scopes: scopes.stream,
      build: (_) =>
          StreamController<String>(onCancel: () => cancelled = true).stream,
      empty: 'empty',
    ).listen(values.add, onError: errors.add);

    scopes.add('home');
    await settle();
    scopes.add(null);
    await settle();

    expect(cancelled, isTrue);
    expect(values, ['empty']);
  });

  test('cancelling stops a pending retry and the listener', () async {
    final query = FakeQuery([denied]);
    listen(query, retryDelay: const Duration(milliseconds: 10));

    scopes.add('home');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await sub?.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(query.listens, ['home']);
    expect(scopes.hasListener, isFalse);
  });

  test('errors from the scopes are passed on', () async {
    listen(FakeQuery([]));

    scopes.addError(StateError('membership'));
    await settle();

    expect(errors.single, isA<StateError>());
  });

  test('only permission-denied counts as transient', () {
    expect(isTransientDenial(denied), isTrue);
    expect(
      isTransientDenial(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
      isFalse,
    );
    expect(isTransientDenial(StateError('x')), isFalse);
  });
}
