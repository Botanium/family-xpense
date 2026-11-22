import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How an unlock attempt ended.
@immutable
sealed class UnlockOutcome {
  const new();

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Face ID, or the passcode fallback, confirmed the owner.
final class Unlocked extends UnlockOutcome {
  /// Creates the outcome.
  const new();
}

/// The user, or iOS (for example a call coming in), dismissed the prompt.
/// The lock stays; the user can try again.
final class UnlockCancelled extends UnlockOutcome {
  /// Creates the outcome.
  const new();
}

/// The iPhone has no passcode, so there is nothing to check against. A lock
/// would only shut the owner out.
final class UnlockUnavailable extends UnlockOutcome {
  /// Creates the outcome.
  const new();
}

/// iOS has locked authentication for a while after too many attempts.
final class UnlockLockedOut extends UnlockOutcome {
  /// Creates the outcome.
  const new();
}

/// Anything else; the error was logged where it was caught.
final class UnlockFailed extends UnlockOutcome {
  /// Creates the outcome.
  const new();
}

/// Face ID with the passcode as fallback (ARCHITECTURE 3.2, BACKLOG S1.2).
abstract interface class BiometricLock {
  /// Asks iOS to confirm the owner. [reason] is shown in the passcode
  /// prompt; Face ID itself shows the `NSFaceIDUsageDescription` text.
  ///
  /// Never throws: every way it can end is an [UnlockOutcome].
  Future<UnlockOutcome> authenticate({required String reason});
}

/// The [BiometricLock] for this run. Throws until the composition root sets
/// it.
final biometricLockProvider = Provider<BiometricLock>(
  (ref) =>
      throw UnimplementedError('biometricLockProvider is set in bootstrap()'),
  name: 'biometricLockProvider',
);
