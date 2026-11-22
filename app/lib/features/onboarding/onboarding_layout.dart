import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/data/auth_repository.dart';

// The frame, headline, paragraph and message widgets moved to core/ui
// (WP-12) so household setup and joining can use them too.
export 'package:xpense_app/core/ui/onboarding_frame.dart';

/// The words for a sign-in failure that belongs to no field, or null when
/// there is nothing to say: a cancel says nothing, and offline shows the
/// banner instead.
String? authFailureMessage(AppLocalizations l10n, AuthFailure failure) =>
    switch (failure) {
      AuthCancelled() || AuthOffline() => null,
      AuthTooManyAttempts() => l10n.onboardingErrorTooMany,
      AuthAccountDisabled() => l10n.onboardingErrorDisabled,
      AuthOtherMethod() => l10n.onboardingErrorOtherMethod,
      AuthMethodUnavailable() => l10n.onboardingErrorUnavailable,
      // Field failures are shown under their field by the email form; from
      // Apple or Google they mean the provider's token was refused.
      AuthInvalidEmail() ||
      AuthEmailInUse() ||
      AuthWeakPassword() ||
      AuthWrongCredentials() ||
      AuthUnknown() => l10n.onboardingErrorUnknown,
    };
