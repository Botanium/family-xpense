// A snapshot listener that is started again when the rules refuse it
// right after this phone founded or joined the household: the founding
// batch shows the membership locally before the server has it (WP-12
// hand-over), so a listener started then gets `permission-denied` and
// Firestore stops it. Same rule as `FirebaseAccountsRepository._retryLater`
// (Codex review, PR #39).
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// Whether [error] is the rules refusing a read.
bool isPermissionDenied(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

/// How many times a refused listener is started again.
const int listenRetries = 6;

/// The first wait before starting a refused listener again; it doubles.
const Duration listenRetryDelay = Duration(milliseconds: 500);

/// Listens to `listen(scope)` for the current [scope], and starts it again
/// when it is refused.
///
/// - While there is no scope (not in a household) it emits [empty].
/// - When the listener fails with an error [refused] accepts, it emits
///   [empty] (the screen says "not found" meanwhile) and starts it again
///   after [delay], doubling each time, up to [retries] times. If the
///   scope changed in between, it starts afresh for the new one.
/// - Any other error is passed on.
Stream<T> listenWithRetry<T, S extends Object>({
  required S? Function() scope,
  required Stream<T> Function(S scope) listen,
  required T empty,
  required bool Function(Object error) refused,
  Duration delay = listenRetryDelay,
  int retries = listenRetries,
}) {
  late final StreamController<T> controller;
  StreamSubscription<T>? inner;
  Timer? timer;
  var active = false;

  void start(int attempt) {
    final current = scope();
    if (current == null) {
      controller.add(empty);
      return;
    }
    inner = listen(current).listen(
      controller.add,
      onError: (Object error, StackTrace stack) {
        if (!refused(error)) {
          controller.addError(error, stack);
          return;
        }
        unawaited(inner?.cancel());
        inner = null;
        controller.add(empty);
        if (attempt >= retries) return;
        timer = Timer(delay * (1 << attempt), () {
          if (!active) return;
          start(scope() == current ? attempt + 1 : 0);
        });
      },
    );
  }

  controller = StreamController<T>(
    onListen: () {
      active = true;
      start(0);
    },
    onCancel: () async {
      active = false;
      timer?.cancel();
      await inner?.cancel();
    },
  );
  return controller.stream;
}
