/// Typed refusals from the context provider.
library;

import 'package:genkit/genkit.dart';

/// Why the context provider refused a request.
///
/// The HTTP error body is Genkit's `{code, status, message}`; `message` is
/// exactly [code], a stable string the phone switches on (ARCHITECTURE 4.4).
/// Nothing else about the failure (token contents, SDK messages, ids) is sent.
enum AuthFailure {
  /// No `Authorization: Bearer <Firebase ID token>` header.
  missingIdToken('missing_id_token', StatusCode.unauthenticated),

  /// The ID token is expired, revoked, malformed, for another project, or the
  /// user is disabled. The phone refreshes the token and retries once.
  invalidIdToken('invalid_id_token', StatusCode.unauthenticated),

  /// No `X-Firebase-AppCheck` header.
  missingAppCheck('missing_app_check', StatusCode.unauthenticated),

  /// The App Check token did not verify.
  invalidAppCheck('invalid_app_check', StatusCode.unauthenticated),

  /// The user has no household yet (`users/{uid}.householdId` is unset).
  noHousehold('no_household', StatusCode.permissionDenied),

  /// The user's household does not list them as a member.
  notMember('not_member', StatusCode.permissionDenied),

  /// The member is in On-device mode; AI routes are refused even if the phone
  /// asks (defence in depth, ARCHITECTURE 4.4).
  onDeviceMode('on_device_mode', StatusCode.permissionDenied),

  /// The household reached a daily limit (ARCHITECTURE 4.5).
  overLimit('over_limit', StatusCode.resourceExhausted),

  /// A backend needed for the checks (Auth, App Check keys, Firestore) could
  /// not be reached. Safe to retry later.
  unavailable('auth_unavailable', StatusCode.unavailable);

  new(this.code, this.status);

  /// The stable error code sent as the error message.
  final String code;

  /// The Genkit status, which sets the HTTP status (401, 403, 429, 503).
  final StatusCode status;

  /// The exception the context provider throws; Genkit answers with
  /// [status] and [code].
  GenkitException toException() => GenkitException(code, status: status);
}

/// Thrown inside the auth module; turned into [AuthFailure.toException] at
/// the provider boundary.
final class AuthRejection implements Exception {
  /// Creates a rejection.
  const new(this.failure);

  /// The reason.
  final AuthFailure failure;

  @override
  String toString() => 'AuthRejection(${failure.code})';
}
