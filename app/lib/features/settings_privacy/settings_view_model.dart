import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/services/biometric_lock.dart';
import 'package:xpense_app/services/settings_store.dart';

/// Why turning the lock on did not work, shown under the switch.
enum FaceIdNotice {
  /// The iPhone has no passcode, so there is nothing to lock with.
  unavailable,

  /// iOS has locked authentication for a while.
  lockedOut,

  /// Anything else.
  failed,
}

/// The Settings screen's own state. The settings themselves are read from
/// `appSettingsProvider`, the single source of truth; this holds only what
/// the screen adds.
@immutable
final class SettingsViewState {
  /// Creates a state.
  const new({this.confirmingFaceId = false, this.faceIdNotice});

  /// Whether the Face ID prompt for turning the lock on is up.
  final bool confirmingFaceId;

  /// Why the last attempt to turn the lock on failed.
  final FaceIdNotice? faceIdNotice;

  @override
  bool operator ==(Object other) =>
      other is SettingsViewState &&
      other.confirmingFaceId == confirmingFaceId &&
      other.faceIdNotice == faceIdNotice;

  @override
  int get hashCode => Object.hash(confirmingFaceId, faceIdNotice);
}

/// View model of Settings (DESIGN_SYSTEM screen 20, skeleton).
///
/// Appearance and the Face ID lock live here now; privacy mode, the
/// exchange rate, categories, export and account join with their packages
/// (WP-70, WP-24, WP-62, WP-82).
final class SettingsViewModel extends Notifier<SettingsViewState> {
  @override
  SettingsViewState build() => const SettingsViewState();

  /// Switches the theme. The new theme paints once the choice is saved.
  void setAppearance(AppearanceMode mode) =>
      unawaited(_update((s) => s.copyWith(appearance: mode)));

  /// Turns the Face ID lock on or off. Turning it on first asks for Face ID
  /// (or the passcode), so nobody can lock themselves out by accident.
  /// [reason] is the localized text iOS shows in the passcode prompt.
  void setFaceIdLock({required bool on, required String reason}) {
    if (state.confirmingFaceId) return;
    if (!on) {
      state = const SettingsViewState();
      unawaited(_update((s) => s.copyWith(faceIdLock: false)));
      return;
    }
    state = const SettingsViewState(confirmingFaceId: true);
    unawaited(_confirmAndEnable(reason));
  }

  Future<void> _confirmAndEnable(String reason) async {
    final UnlockOutcome outcome;
    try {
      outcome = await ref
          .read(biometricLockProvider)
          .authenticate(reason: reason);
    } on Object catch (error, stack) {
      _report(error, stack);
      if (ref.mounted) {
        state = const SettingsViewState(faceIdNotice: FaceIdNotice.failed);
      }
      return;
    }
    if (!ref.mounted) return;
    final notice = switch (outcome) {
      Unlocked() || UnlockCancelled() => null,
      UnlockUnavailable() => FaceIdNotice.unavailable,
      UnlockLockedOut() => FaceIdNotice.lockedOut,
      UnlockFailed() => FaceIdNotice.failed,
    };
    state = SettingsViewState(faceIdNotice: notice);
    if (outcome is Unlocked) {
      await _update((s) => s.copyWith(faceIdLock: true));
    }
  }

  // Each change is applied to the latest settings, never to a snapshot
  // taken here, so overlapping changes do not undo each other.
  Future<void> _update(AppSettings Function(AppSettings) change) async {
    try {
      await ref.read(appSettingsProvider.notifier).update(change);
    } on Object catch (error, stack) {
      // The switch and chips show the stored value, which did not change,
      // so the screen already tells the truth; the error is logged.
      _report(error, stack);
    }
  }

  void _report(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'SettingsViewModel',
    ),
  );
}

/// The Settings screen's view model.
final NotifierProvider<SettingsViewModel, SettingsViewState>
settingsViewModelProvider =
    NotifierProvider.autoDispose<SettingsViewModel, SettingsViewState>(
      SettingsViewModel.new,
      name: 'settingsViewModelProvider',
    );
