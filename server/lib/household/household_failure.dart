/// Typed refusals of the household flows.
library;

import 'package:genkit/genkit.dart';

/// Why `/household/invite` or `/household/join` refused.
///
/// Like `AuthFailure`, the HTTP error body is Genkit's
/// `{code, status, message}` and `message` is exactly [code], a stable
/// string the phone switches on. Nothing else (ids, names, the code) is sent.
enum HouseholdFailure {
  /// The display name is empty or longer than the limit.
  invalidName('invalid_name', StatusCode.invalidArgument),

  /// The input is not the expected shape.
  invalidInput('invalid_input', StatusCode.invalidArgument),

  /// No live invite has this code. Malformed, unknown, revoked and
  /// never-issued codes look the same, so a guess learns nothing.
  inviteInvalid('invite_invalid', StatusCode.notFound),

  /// The invite is older than its 7 days.
  inviteExpired('invite_expired', StatusCode.failedPrecondition),

  /// Someone already joined with this invite (single use).
  inviteUsed('invite_used', StatusCode.failedPrecondition),

  /// The household already has two members (DATA_MODEL 2.2).
  householdFull('household_full', StatusCode.failedPrecondition),

  /// The caller's household does not list them (an invite needs a member).
  notMember('not_member', StatusCode.permissionDenied),

  /// The caller already belongs to another household (one per user in v1).
  alreadyInHousehold('already_in_household', StatusCode.failedPrecondition),

  /// The caller made too many invite or join attempts recently.
  rateLimited('rate_limited', StatusCode.resourceExhausted),

  /// Firestore could not be reached. Safe to retry.
  unavailable('household_unavailable', StatusCode.unavailable);

  new(this.code, this.status);

  /// The stable error code sent as the error message.
  final String code;

  /// The Genkit status, which sets the HTTP status.
  final StatusCode status;

  /// The exception a flow throws; Genkit answers with [status] and [code].
  GenkitException toException() => GenkitException(code, status: status);
}

/// Thrown inside the household module; turned into
/// [HouseholdFailure.toException] at the flow boundary.
final class HouseholdRejection implements Exception {
  /// Creates a rejection.
  const new(this.failure);

  /// The reason.
  final HouseholdFailure failure;

  @override
  String toString() => 'HouseholdRejection(${failure.code})';
}
