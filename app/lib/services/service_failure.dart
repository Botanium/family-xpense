import 'package:flutter/foundation.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Why a native or remote service could not do what it was asked
/// (ARCHITECTURE 3.2).
///
/// Services return these in a [Result] instead of throwing, so callers
/// switch over every case. A failure carries a stable [code] and never a
/// user-facing string; the screen picks the words from the ARB file.
@immutable
sealed class ServiceFailure implements Failure {
  const new();

  // Field-less failures are equal when they are the same case.
  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => code;
}

/// The phone has no connection, or the backend did not answer.
final class ServiceOffline extends ServiceFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'service.offline';
}

/// The capability does not exist on this phone or in this privacy mode,
/// such as on-device recognition on an older iPhone.
final class ServiceUnavailable extends ServiceFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'service.unavailable';
}

/// The user declined a permission the service needs (microphone, speech,
/// camera).
final class ServicePermissionDenied extends ServiceFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'service.permission_denied';
}

/// The backend refused the call because a per-household limit was reached.
final class ServiceRateLimited extends ServiceFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'service.rate_limited';
}

/// The call was cancelled before it finished.
final class ServiceCancelled extends ServiceFailure {
  /// Creates the failure.
  const new();

  @override
  String get code => 'service.cancelled';
}

/// Anything else. The original error is logged where it was caught, before
/// this value is returned.
final class ServiceError extends ServiceFailure {
  /// Creates the failure with a short machine-readable [detail].
  const new(this.detail);

  /// A short machine-readable reason, such as an HTTP status or a plugin
  /// error code. Never shown to the user.
  final String detail;

  @override
  String get code => 'service.error';

  @override
  bool operator ==(Object other) =>
      other is ServiceError && other.detail == detail;

  @override
  int get hashCode => Object.hash(ServiceError, detail);
}
