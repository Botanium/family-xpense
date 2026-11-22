import 'dart:async';

import 'package:xpense_app/services/biometric_lock.dart';

/// A [BiometricLock] that answers with [outcome], for tests and for runs
/// on a machine without Face ID.
final class FakeBiometricLock implements BiometricLock {
  /// Creates a lock that answers every prompt with [outcome].
  new({this.outcome = const Unlocked()});

  /// What the next prompt answers.
  UnlockOutcome outcome;

  /// When set, prompts wait for this to complete before answering, so a
  /// test can observe the "asking" state.
  Completer<void>? gate;

  /// The reasons passed to [authenticate], in order.
  final List<String> reasons = [];

  @override
  Future<UnlockOutcome> authenticate({required String reason}) async {
    reasons.add(reason);
    await gate?.future;
    return outcome;
  }
}
