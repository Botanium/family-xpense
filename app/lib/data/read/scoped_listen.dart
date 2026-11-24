// The one live-query helper for the readers in `data/read/` (Entry,
// Activity, Home) and the household-scoped repositories (FX rates,
// categories): it follows the signed-in member's household and retries a
// transient refusal.
//
// Right after a household is created or joined, the founding batch can
// report `InHousehold` from the phone's cache before the server has accepted
// the membership; the same happens for a moment after an account's
// visibility changes. A listener started then is refused with
// `permission-denied`, and Firestore ends it; nothing would start it again
// while the scope stays the same. [scopedListen] retries such a refusal with
// a doubling delay while the scope is unchanged (Codex reviews, PRs #37,
// #38 and #39).
//
// No Firestore import: the caller passes the scopes and the queries, so
// this is tested without Firebase. [isTransientDenial] only needs the
// exception type from `firebase_core`.
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';

/// How many times [scopedListen] retries by default.
const int scopedListenRetries = 6;

/// The first retry delay of [scopedListen] by default; each retry doubles it.
const Duration scopedListenRetryDelay = Duration(milliseconds: 500);

/// Whether [error] is the refusal a listener can meet while a new
/// membership (or a visibility change) reaches the server: worth retrying.
bool isTransientDenial(Object error) =>
    error is FirebaseException && error.code == 'permission-denied';

/// Emits what [build] emits for the latest scope from [scopes], restarting
/// it whenever the scope changes (by `==`), and [empty] while the scope is
/// null (signed out, or not in a household).
///
/// - **Retry:** when the inner stream fails with an error [isTransient]
///   accepts, it is cancelled and started again after [retryDelay], then
///   twice that, up to [retries] times, as long as the scope has not
///   changed meanwhile. A successful event resets the count. With
///   [emptyWhileRetrying], [empty] is emitted while a retry waits (Entry
///   detail reads "not found" meanwhile).
/// - **Errors:** any other error, and a transient one after the last
///   retry, is passed on and ends the inner listener (as Firestore ends a
///   listener on an error). The same scope emitted again then listens
///   anew; while a listener is live or a retry waits, the same scope is
///   ignored. Errors from [scopes] are passed on.
/// - **Cancel:** cancelling the result cancels the scope subscription, the
///   inner listener and any waiting retry; a late event or retry from an
///   older scope does nothing.
Stream<T> scopedListen<S extends Object, T>({
  required Stream<S?> scopes,
  required Stream<T> Function(S scope) build,
  required T empty,
  bool Function(Object error) isTransient = isTransientDenial,
  int retries = scopedListenRetries,
  Duration retryDelay = scopedListenRetryDelay,
  bool emptyWhileRetrying = false,
}) {
  late final StreamController<T> controller;
  StreamSubscription<S?>? scopeSub;
  StreamSubscription<T>? inner;
  Timer? retry;
  var started = false;
  // The inner listener ended on an error that was passed on.
  var ended = false;
  S? current;
  // Bumped on every scope change and on cancel, so a late retry or a late
  // event from an old listener does nothing.
  var generation = 0;

  void stopInner() {
    retry?.cancel();
    retry = null;
    unawaited(inner?.cancel());
    inner = null;
  }

  void start(S scope, int attempt) {
    final mine = generation;
    var failures = attempt;
    ended = false;
    inner = build(scope).listen(
      (value) {
        if (mine != generation || controller.isClosed) return;
        failures = 0;
        controller.add(value);
      },
      onError: (Object error, StackTrace stack) {
        if (mine != generation || controller.isClosed) return;
        stopInner();
        if (isTransient(error) && failures < retries) {
          final delay = retryDelay * (1 << failures);
          final next = failures + 1;
          if (emptyWhileRetrying) controller.add(empty);
          retry = Timer(delay, () {
            retry = null;
            if (mine == generation && !controller.isClosed) start(scope, next);
          });
          return;
        }
        ended = true;
        controller.addError(error, stack);
      },
    );
  }

  void follow(S? scope) {
    if (started && scope == current && !ended) return;
    started = true;
    current = scope;
    generation++;
    stopInner();
    if (scope == null) {
      ended = false;
      controller.add(empty);
      return;
    }
    start(scope, 0);
  }

  controller = StreamController<T>(
    onListen: () {
      scopeSub = scopes.listen(
        follow,
        onError: (Object error, StackTrace stack) {
          if (!controller.isClosed) controller.addError(error, stack);
        },
      );
    },
    onCancel: () async {
      generation++;
      retry?.cancel();
      retry = null;
      final listener = inner;
      inner = null;
      await scopeSub?.cancel();
      await listener?.cancel();
    },
  );
  return controller.stream;
}
