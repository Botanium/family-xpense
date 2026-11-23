import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/features/household/household_setup_view_model.dart';
import 'package:xpense_app/features/household/join_view_model.dart';

/// The words under a name field, or null when there is no problem.
/// [empty] replaces the household-name wording for the person's own name.
String? nameProblemMessage(
  AppLocalizations l10n,
  NameProblem? problem, {
  String? empty,
}) => switch (problem) {
  null => null,
  NameProblem.empty => empty ?? l10n.householdNameErrorEmpty,
  NameProblem.tooLong => l10n.householdNameErrorLong(maxHouseholdNameLength),
};

/// The words under the invite code field, or null.
String? codeProblemMessage(AppLocalizations l10n, CodeProblem? problem) =>
    switch (problem) {
      null => null,
      CodeProblem.empty => l10n.householdJoinCodeErrorEmpty,
      CodeProblem.shape => l10n.householdJoinCodeErrorShape,
    };

/// The words for a failure while creating the household or joining one.
/// Offline shows the banner instead, but has words for completeness.
String householdFailureMessage(
  AppLocalizations l10n,
  HouseholdFailure failure,
) => switch (failure) {
  HouseholdOffline() => l10n.householdOffline,
  InviteInvalid() => l10n.householdJoinErrorInvalid,
  InviteExpired() => l10n.householdJoinErrorExpired,
  InviteUsed() => l10n.householdJoinErrorUsed,
  HouseholdFull() => l10n.householdJoinErrorFull,
  AlreadyInHousehold() => l10n.householdJoinErrorAlready,
  HouseholdRateLimited() => l10n.householdJoinErrorRateLimited,
  HouseholdNotAllowed() => l10n.householdErrorNotAllowed,
  HouseholdServiceUnavailable() => l10n.householdInviteUnavailable,
  HouseholdUnknown() => l10n.householdErrorUnknown,
};

/// The words in place of the invite code when it could not be made.
String inviteFailureMessage(AppLocalizations l10n, HouseholdFailure failure) =>
    switch (failure) {
      HouseholdOffline() => l10n.householdInviteOffline,
      HouseholdServiceUnavailable() => l10n.householdInviteUnavailable,
      HouseholdRateLimited() => l10n.householdInviteRateLimited,
      HouseholdNotAllowed() => l10n.householdErrorNotAllowed,
      HouseholdFull() => l10n.householdInviteFull,
      InviteInvalid() ||
      InviteExpired() ||
      InviteUsed() ||
      AlreadyInHousehold() ||
      HouseholdUnknown() => l10n.householdInviteFailed,
    };
