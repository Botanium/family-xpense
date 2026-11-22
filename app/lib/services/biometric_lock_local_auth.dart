import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import 'package:xpense_app/services/biometric_lock.dart';

/// [BiometricLock] over `local_auth` 3.
///
/// `biometricOnly` is off, so iOS falls back to the device passcode when
/// Face ID fails or is not enrolled (BACKLOG S1.2).
final class LocalAuthBiometricLock implements BiometricLock {
  /// Creates the adapter; [auth] is replaceable for tests.
  new({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<UnlockOutcome> authenticate({required String reason}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // Resume the prompt if iOS interrupts it by backgrounding the app.
        persistAcrossBackgrounding: true,
      );
      return ok ? const Unlocked() : const UnlockCancelled();
    } on LocalAuthException catch (error, stack) {
      return outcomeFor(error.code, error, stack);
    } on PlatformException catch (error, stack) {
      _log(error, stack);
      return const UnlockFailed();
    }
  }

  /// Maps a `local_auth` error code to an outcome. Codes added to the
  /// plugin later fall through to [UnlockFailed] (the plugin documents
  /// that its enum grows).
  @visibleForTesting
  static UnlockOutcome outcomeFor(
    LocalAuthExceptionCode code, [
    Object? error,
    StackTrace? stack,
  ]) {
    switch (code) {
      case LocalAuthExceptionCode.userCanceled:
      case LocalAuthExceptionCode.systemCanceled:
      case LocalAuthExceptionCode.timeout:
      case LocalAuthExceptionCode.authInProgress:
        return const UnlockCancelled();
      case LocalAuthExceptionCode.noCredentialsSet:
        return const UnlockUnavailable();
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return const UnlockLockedOut();
      // The plugin documents that this enum grows, so a default is needed.
      // ignore: no_default_cases
      default:
        if (error != null) _log(error, stack);
        return const UnlockFailed();
    }
  }

  static void _log(Object error, StackTrace? stack) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'BiometricLock',
      context: ErrorDescription('while asking for Face ID or the passcode'),
    ),
  );
}
