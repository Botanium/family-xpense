import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/clock.dart';
import 'package:xpense_app/services/settings_store.dart';

/// When the lock comes back (ARCHITECTURE 3.3, BACKLOG S1.2).
abstract final class LockPolicy {
  /// Seconds in the background after which the app locks again.
  static const int backgroundGraceSeconds = 60;
}

/// Why the last unlock attempt did not open the app.
enum LockNotice {
  /// iOS has locked authentication for a while.
  lockedOut,

  /// Anything else; the user can try again.
  failed,
}

/// What the lock gate shows.
@immutable
final class AppLockState {
  /// Creates a state; the default is open.
  const new({
    this.locked = false,
    this.obscured = false,
    this.authenticating = false,
    this.notice,
    this.promptRequest = 0,
  });

  /// Whether the lock overlay covers the app until the owner unlocks it.
  final bool locked;

  /// Whether the app is covered for the app switcher. The cover goes away
  /// when the app is active again.
  final bool obscured;

  /// Whether a Face ID or passcode prompt is up.
  final bool authenticating;

  /// Why the last attempt failed, shown under the unlock button.
  final LockNotice? notice;

  /// Goes up each time the app wants Face ID asked for without a tap: on a
  /// cold start, and on returning from the background while locked. The
  /// gate answers each new value with [AppLockController.promptIfRequested].
  final int promptRequest;

  @override
  bool operator ==(Object other) =>
      other is AppLockState &&
      other.locked == locked &&
      other.obscured == obscured &&
      other.authenticating == authenticating &&
      other.notice == notice &&
      other.promptRequest == promptRequest;

  @override
  int get hashCode =>
      Object.hash(locked, obscured, authenticating, notice, promptRequest);

  @override
  String toString() =>
      'AppLockState(locked: $locked, obscured: $obscured, '
      'authenticating: $authenticating, notice: $notice, '
      'promptRequest: $promptRequest)';
}

/// The Face ID lock (ARCHITECTURE 3.3, BACKLOG S1.2).
///
/// With the lock on: the app starts locked; after
/// [LockPolicy.backgroundGraceSeconds] in the background it locks again;
/// while it is not active (app switcher, Control Center) its content is
/// covered. Turning the lock off opens the app at once.
///
/// The root's lifecycle observer feeds [onLifecycle]; the gate widget
/// calls [promptIfRequested] and [unlock].
final class AppLockController extends Notifier<AppLockState> {
  DateTime? _backgroundedAt;

  // The last prompt request answered by a prompt.
  int _answered = 0;

  @override
  AppLockState build() {
    ref.listen(appSettingsProvider.select((s) => s.faceIdLock), (_, on) {
      if (on) return;
      _backgroundedAt = null;
      state = AppLockState(promptRequest: state.promptRequest);
    });
    final on = ref.read(appSettingsProvider).faceIdLock;
    return on
        ? const AppLockState(locked: true, promptRequest: 1)
        : const AppLockState();
  }

  bool get _enabled => ref.read(appSettingsProvider).faceIdLock;

  /// Applies an app lifecycle change.
  void onLifecycle(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.inactive:
        _cover();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _backgroundedAt ??= ref.read(clockProvider).now();
        _cover();
      case AppLifecycleState.resumed:
        _resume();
      case AppLifecycleState.detached:
        break;
    }
  }

  void _cover() {
    if (!_enabled || state.locked || state.obscured) return;
    state = AppLockState(obscured: true, promptRequest: state.promptRequest);
  }

  void _resume() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    final current = state;
    if (!_enabled) {
      if (current.obscured) {
        state = AppLockState(promptRequest: current.promptRequest);
      }
      return;
    }
    // Only a real trip to the background counts. The Face ID prompt itself
    // makes the app inactive and then active again; prompting again then
    // would loop after a cancel.
    final away = since == null
        ? null
        : ref.read(clockProvider).now().difference(since).inSeconds;
    final expired = away != null && away >= LockPolicy.backgroundGraceSeconds;
    if (current.locked) {
      // Ask again after a trip to the background, or when a request could
      // not be answered yet (a cold start before the app was active).
      final unanswered = current.promptRequest > _answered;
      if (!current.authenticating && (away != null || unanswered)) {
        state = AppLockState(
          locked: true,
          notice: current.notice,
          promptRequest: current.promptRequest + 1,
        );
      }
    } else if (expired) {
      state = AppLockState(
        locked: true,
        promptRequest: current.promptRequest + 1,
      );
    } else if (current.obscured) {
      state = AppLockState(promptRequest: current.promptRequest);
    }
  }

  /// Answers a prompt request that no prompt has answered yet by calling
  /// [unlock]. The gate calls it when the app is active.
  void promptIfRequested({required String reason}) {
    if (state.promptRequest > _answered) unlock(reason: reason);
  }

  /// Asks for Face ID, with the passcode as fallback. [reason] is the
  /// localized text iOS shows in the passcode prompt. Does nothing when
  /// the app is open or a prompt is already up.
  void unlock({required String reason}) {
    final current = state;
    if (!current.locked || current.authenticating) return;
    _answered = current.promptRequest;
    state = AppLockState(
      locked: true,
      authenticating: true,
      promptRequest: current.promptRequest,
    );
    unawaited(_authenticate(reason).catchError(_report));
  }

  Future<void> _authenticate(String reason) async {
    final outcome = await ref
        .read(biometricLockProvider)
        .authenticate(reason: reason);
    if (!ref.mounted) return;
    final request = state.promptRequest;
    state = switch (outcome) {
      // Without a passcode there is nothing to check against; locking would
      // only shut the owner out of their own data.
      Unlocked() || UnlockUnavailable() => AppLockState(promptRequest: request),
      UnlockCancelled() => AppLockState(locked: true, promptRequest: request),
      UnlockLockedOut() => AppLockState(
        locked: true,
        notice: LockNotice.lockedOut,
        promptRequest: request,
      ),
      UnlockFailed() => AppLockState(
        locked: true,
        notice: LockNotice.failed,
        promptRequest: request,
      ),
    };
  }

  void _report(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'AppLockController',
      ),
    );
    if (!ref.mounted) return;
    state = AppLockState(
      locked: true,
      notice: LockNotice.failed,
      promptRequest: state.promptRequest,
    );
  }
}

/// The app lock.
final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(
      AppLockController.new,
      name: 'appLockControllerProvider',
    );
