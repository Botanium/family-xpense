// A live query that follows the signed-in member's household and retries a
// transient refusal, for the readers in `data/read/` (Home, Activity, Entry).
//
// Right after a household is created or joined, the founding batch can
// report `InHousehold` from the phone's cache before the server has accepted
// the membership. A listener started then is refused with
// `permission-denied`, and Firestore ends it; nothing would start it again
// while the scope stays the same. [scopedListen] retries such a refusal with
// a doubling delay while the scope is unchanged, as
// `FirebaseAccountsRepository` does for its own listeners (Codex review,
// PR #37).
//
// Pure Dart, no Firestore import: the caller says which errors are
// transient, so this is tested without Firebase.
import 'dart:async';

/// How many times [scopedListen] retries by default.
const int scopedListenRetries = 6;

/// The first retry delay of [scopedListen] by default; each retry doubles it.
const Duration scopedListenRetryDelay = Duration(milliseconds: 500);

/// Emits what [build] emits for the latest scope from [scopes], restarting
/// it whenever the scope changes (by `==`), and [empty] while the scope is
/// null (signed out, or not in a household).
///
/// When the inner stream fails with an error [isTransient] accepts, it is
/// dropped and started again after [retryDelay], then twice that, up to
/// [retries] times, as long as the scope has not changed meanwhile. A
/// successful event resets the count. Other errors, and a transient one
/// after the last retry, are passed on.
Stream<T> scopedListen<S extends Object, T>({
  required Stream<S?> scopes,
  required Stream<T> Function(S scope) build,
  required T empty,
  required bool Function(Object error) isTransient,
  int retries = scopedListenRetries,
  Duration retryDelay = scopedListenRetryDelay,
}) {
  late final StreamController<T> controller;
  StreamSubscription<S?>? scopeSub;
  StreamSubscription<T>? inner;
  Timer? retry;
  var started = false;
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
    inner = build(scope).listen(
      (value) {
        if (mine != generation) return;
        failures = 0;
        controller.add(value);
      },
      onError: (Object error, StackTrace stack) {
        if (mine != generation) return;
        if (isTransient(error) && failures < retries) {
          final delay = retryDelay * (1 << failures);
          final next = failures + 1;
          stopInner();
          retry = Timer(delay, () {
            if (mine == generation && !controller.isClosed) start(scope, next);
          });
          return;
        }
        controller.addError(error, stack);
      },
    );
  }

  void follow(S? scope) {
    if (started && scope == current) return;
    started = true;
    current = scope;
    generation++;
    stopInner();
    if (scope == null) {
      controller.add(empty);
      return;
    }
    start(scope, 0);
  }

  controller = StreamController<T>(
    onListen: () {
      scopeSub = scopes.listen(follow, onError: controller.addError);
    },
    onCancel: () async {
      generation++;
      retry?.cancel();
      await scopeSub?.cancel();
      await inner?.cancel();
    },
  );
  return controller.stream;
}
