import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/onboarding/email_view_model.dart';
import 'package:xpense_app/features/onboarding/onboarding_layout.dart';

/// The email and password form behind "Continue with email" (part of
/// screen 2). No artboard exists for it; it follows Create account's frame
/// with `XpTextField`s and one primary button.
///
/// Messages sit under the field they are about; failures that belong to
/// neither field sit under the fields, and offline shows the banner.
class EmailScreen extends ConsumerStatefulWidget {
  /// Creates the form, opened in [mode].
  const new({this.mode = EmailMode.create, super.key});

  /// Create an account or sign in, from the route.
  final EmailMode mode;

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  EmailViewModel get _viewModel =>
      ref.read(emailViewModelProvider(widget.mode).notifier);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() => unawaited(
    _viewModel.submit(email: _email.text, password: _password.text),
  );

  void _retry() =>
      unawaited(_viewModel.retry(email: _email.text, password: _password.text));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(emailViewModelProvider(widget.mode));
    final creating = state.mode == EmailMode.create;
    final failure = state.failure;
    final message = failure == null ? null : authFailureMessage(l10n, failure);
    final resetSentTo = state.resetSentTo;
    return OnboardingFrame(
      topBar: XpTopBar(
        title: creating
            ? l10n.onboardingEmailCreateTitle
            : l10n.onboardingEmailSignInTitle,
        leading: const XpBackButton(),
      ),
      banner: state.offline
          ? OfflineBanner(
              message: l10n.onboardingOffline,
              actionLabel: l10n.onboardingRetry,
              onAction: state.locked ? null : _retry,
            )
          : null,
      content: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepBar(
              current: 1,
              semanticLabel: l10n.onboardingStep(1, onboardingStepCount),
            ),
            const SizedBox(height: XpSpace.s24),
            OnboardingHeading(
              creating
                  ? l10n.onboardingEmailCreateHeadline
                  : l10n.onboardingEmailSignInHeadline,
            ),
            const SizedBox(height: XpSpace.s8),
            OnboardingParagraph(
              creating
                  ? l10n.onboardingEmailCreateBody
                  : l10n.onboardingEmailSignInBody,
            ),
            const SizedBox(height: XpSpace.s32),
            XpTextField(
              label: l10n.onboardingEmailLabel,
              controller: _email,
              hint: l10n.onboardingEmailHint,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              enabled: !state.locked,
              error: _emailMessage(l10n, state.emailProblem),
              onChanged: (_) => _viewModel.emailEdited(),
            ),
            const SizedBox(height: XpSpace.s24),
            XpTextField(
              label: l10n.onboardingPasswordLabel,
              controller: _password,
              hint: creating
                  ? l10n.onboardingPasswordHintNew(minPasswordLength)
                  : null,
              obscureText: true,
              autofillHints: [
                if (creating)
                  AutofillHints.newPassword
                else
                  AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              enabled: !state.locked,
              error: _passwordMessage(l10n, state.passwordProblem),
              onChanged: (_) => _viewModel.passwordEdited(),
              onSubmitted: (_) => _submit(),
            ),
            if (resetSentTo != null) ...[
              const SizedBox(height: XpSpace.s16),
              OnboardingMessage.note(
                l10n.onboardingEmailResetSent(resetSentTo),
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: XpSpace.s16),
              OnboardingMessage.error(message),
            ],
            const SizedBox(height: XpSpace.s32),
            XpButton.primary(
              label: state.busy || state.signedIn
                  ? l10n.onboardingSigningIn
                  : creating
                  ? l10n.onboardingEmailCreateAction
                  : l10n.onboardingEmailSignInAction,
              onPressed: state.locked ? null : _submit,
            ),
            const SizedBox(height: XpSpace.s8),
            XpButton.text(
              label: creating
                  ? l10n.onboardingEmailSwitchToSignIn
                  : l10n.onboardingEmailSwitchToCreate,
              expand: true,
              onPressed: state.locked ? null : _viewModel.toggleMode,
            ),
            if (!creating)
              XpButton.text(
                label: l10n.onboardingEmailForgot,
                expand: true,
                onPressed: state.locked
                    ? null
                    : () => unawaited(_viewModel.forgotPassword(_email.text)),
              ),
          ],
        ),
      ),
    );
  }

  static String? _emailMessage(AppLocalizations l10n, EmailProblem? problem) =>
      switch (problem) {
        null => null,
        EmailProblem.empty => l10n.onboardingEmailErrorEmpty,
        EmailProblem.invalid => l10n.onboardingEmailErrorInvalid,
        EmailProblem.inUse => l10n.onboardingEmailErrorInUse,
      };

  static String? _passwordMessage(
    AppLocalizations l10n,
    PasswordProblem? problem,
  ) => switch (problem) {
    null => null,
    PasswordProblem.empty => l10n.onboardingPasswordErrorEmpty,
    PasswordProblem.short => l10n.onboardingPasswordErrorShort(
      minPasswordLength,
    ),
    PasswordProblem.weak => l10n.onboardingPasswordErrorWeak,
    PasswordProblem.wrong => l10n.onboardingPasswordErrorWrong,
  };
}
