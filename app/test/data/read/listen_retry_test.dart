import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/data/read/listen_retry.dart';

/// A listener per start: each call to [listen] takes the next script.
final class _Listeners {
  new(this.scripts);

  /// What each start does: a value, or an error.
  final List<Object> scripts;

  /// The scope each start was made for.
  final List<String> scopes = [];

  Stream<String> listen(String scope) {
    scopes.add(scope);
    final step = scripts[(scopes.length - 1).clamp(0, scripts.length - 1)];
    return step is String
        ? Stream.value('$scope:$step')
        : Stream<String>.error(step);
  }
}

final _denied = FirebaseException(
  plugin: 'cloud_firestore',
  code: 'permission-denied',
);

Stream<String> _watch(
  _Listeners listeners, {
  required String? Function() scope,
  int retries = listenRetries,
}) => listenWithRetry<String, String>(
  scope: scope,
  listen: listeners.listen,
  empty: 'empty',
  refused: isPermissionDenied,
  delay: const Duration(milliseconds: 1),
  retries: retries,
);

void main() {
  test('a refused listener is started again and then reads', () async {
    // The founding batch is not on the server yet: refused twice, then ok.
    final listeners = _Listeners([_denied, _denied, 'entry']);
    final seen = await _watch(listeners, scope: () => 'h1').take(3).toList();
    expect(seen, ['empty', 'empty', 'h1:entry']);
    expect(listeners.scopes, ['h1', 'h1', 'h1']);
  });

  test('it gives up after the retries, saying not found', () async {
    final listeners = _Listeners([_denied]);
    final seen = await _watch(
      listeners,
      scope: () => 'h1',
      retries: 2,
    ).take(3).toList();
    expect(seen, ['empty', 'empty', 'empty']);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(listeners.scopes, hasLength(3));
  });

  test('a new scope between retries starts afresh for it', () async {
    var scope = 'h1';
    final listeners = _Listeners([_denied, 'entry']);
    final stream = _watch(listeners, scope: () => scope);
    final seen = <String>[];
    final sub = stream.listen((v) {
      seen.add(v);
      scope = 'h2';
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(listeners.scopes, ['h1', 'h2']);
    expect(seen, ['empty', 'h2:entry']);
  });

  test('no household reads as empty and starts nothing', () async {
    final listeners = _Listeners(['entry']);
    expect(await _watch(listeners, scope: () => null).first, 'empty');
    expect(listeners.scopes, isEmpty);
  });

  test('other errors are passed on, not retried', () async {
    final listeners = _Listeners([StateError('boom')]);
    await expectLater(
      _watch(listeners, scope: () => 'h1'),
      emitsError(isA<StateError>()),
    );
    expect(listeners.scopes, ['h1']);
  });

  test('cancelling stops a pending retry', () async {
    final listeners = _Listeners([_denied]);
    final sub = listenWithRetry<String, String>(
      scope: () => 'h1',
      listen: listeners.listen,
      empty: 'empty',
      refused: isPermissionDenied,
      delay: const Duration(milliseconds: 10),
    ).listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(listeners.scopes, ['h1']);
  });

  test('only permission-denied counts as a refusal', () {
    expect(isPermissionDenied(_denied), isTrue);
    expect(
      isPermissionDenied(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      ),
      isFalse,
    );
    expect(isPermissionDenied(StateError('x')), isFalse);
  });
}
