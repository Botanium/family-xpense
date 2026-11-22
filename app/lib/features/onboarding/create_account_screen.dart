import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/onboarding/create_account_view_model.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';
import 'package:xpense_app/features/onboarding/onboarding_layout.dart';

/// Create account (DESIGN_SYSTEM 9, screen 2; PRD ON-2): Apple, Google and
/// email as three buttons of equal weight, Apple first, with the privacy
/// note and the Terms and Privacy links (DESIGN_SYSTEM 12, item 8).
///
/// A successful sign-in does not navigate from here: the router's
/// onboarding gate sees the new session and moves on.
class CreateAccountScreen extends ConsumerWidget {
  /// Creates the screen; [invite] when the person came to join a partner.
  const new({this.invite = false, this.inviteCode, super.key});

  /// Whether the person came to join a partner's household.
  final bool invite;

  /// An invite code from a link, carried to the join screen.
  final String? inviteCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(createAccountViewModelProvider);
    final viewModel = ref.read(createAccountViewModelProvider.notifier);
    final failure = state.failure;
    final message = failure == null ? null : authFailureMessage(l10n, failure);
    VoidCallback? signIn(ProviderMethod method) =>
        state.locked ? null : () => unawaited(viewModel.signIn(method));
    return OnboardingFrame(
      topBar: XpTopBar(
        title: l10n.onboardingCreateAccountTitle,
        leading: const XpBackButton(),
      ),
      banner: state.offline
          ? OfflineBanner(
              message: l10n.onboardingOffline,
              actionLabel: l10n.onboardingRetry,
              onAction: state.locked
                  ? null
                  : () => unawaited(viewModel.retry()),
            )
          : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepBar(
            current: 1,
            semanticLabel: l10n.onboardingStep(1, onboardingStepCount),
          ),
          const SizedBox(height: XpSpace.s24),
          OnboardingHeading(l10n.onboardingCreateAccountHeadline),
          const SizedBox(height: XpSpace.s8),
          OnboardingParagraph(
            invite
                ? l10n.onboardingCreateAccountInviteBody
                : l10n.onboardingCreateAccountBody,
          ),
          const SizedBox(height: XpSpace.s32),
          SignInButton(
            label: l10n.onboardingContinueApple,
            busy: state.busy == ProviderMethod.apple,
            busyLabel: l10n.onboardingSigningIn,
            onPressed: signIn(ProviderMethod.apple),
          ),
          const SizedBox(height: XpSpace.s12),
          SignInButton(
            label: l10n.onboardingContinueGoogle,
            busy: state.busy == ProviderMethod.google,
            busyLabel: l10n.onboardingSigningIn,
            onPressed: signIn(ProviderMethod.google),
          ),
          const SizedBox(height: XpSpace.s12),
          SignInButton(
            label: l10n.onboardingContinueEmail,
            busy: false,
            busyLabel: l10n.onboardingSigningIn,
            onPressed: state.locked
                ? null
                : () => context.go(
                    OnboardingRoutes.emailWith(
                      invite: invite,
                      code: inviteCode,
                    ),
                  ),
          ),
          if (message != null) ...[
            const SizedBox(height: XpSpace.s16),
            OnboardingMessage.error(message),
          ],
        ],
      ),
      bottom: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PrivacyNote(),
          SizedBox(height: XpSpace.s24),
          _LegalLine(),
        ],
      ),
    );
  }
}

/// One sign-in method: an outline button, with a spinner at its end while
/// that method's sheet is open. All three look alike, so none outweighs
/// the others (App Review 4.8).
class SignInButton extends StatelessWidget {
  /// Creates a sign-in button.
  const new({
    required this.label,
    required this.busy,
    required this.busyLabel,
    required this.onPressed,
    super.key,
  });

  /// "Continue with …".
  final String label;

  /// Whether this method is being tried.
  final bool busy;

  /// Spoken label of the spinner.
  final String busyLabel;

  /// Tap handler; null disables the button.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final button = XpButton.secondary(label: label, onPressed: onPressed);
    if (!busy) return button;
    return Stack(
      alignment: AlignmentDirectional.centerEnd,
      children: [
        button,
        Padding(
          padding: const EdgeInsetsDirectional.only(end: XpSpace.s20),
          child: XpSpinner(semanticLabel: busyLabel),
        ),
      ],
    );
  }
}

/// "Private by default." and what it means.
class _PrivacyNote extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final caption = XpType.of(context).caption;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        XpIcon(XpGlyph.lock, size: XpSpace.iconRow, color: colors.inkSecondary),
        const SizedBox(width: XpSpace.s8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: caption.copyWith(color: colors.inkSecondary),
              children: [
                TextSpan(
                  text: l10n.onboardingPrivacyNoteLead,
                  style: caption.copyWith(
                    color: colors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const TextSpan(text: ' '),
                TextSpan(text: l10n.onboardingPrivacyNoteBody),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "By continuing you agree to the Terms and the Privacy Policy." with both
/// as links. The sentence stays whole in the ARB file; the links are found
/// by placeholder marks.
class _LegalLine extends StatefulWidget {
  const new();

  @override
  State<_LegalLine> createState() => _LegalLineState();
}

class _LegalLineState extends State<_LegalLine> {
  // Private-use characters that never occur in a translation.
  static const String _termsMark = '\u{E000}';
  static const String _privacyMark = '\u{E001}';

  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => unawaited(context.push(OnboardingRoutes.terms));
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => unawaited(context.push(OnboardingRoutes.privacy));

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final meta = XpType.of(context).meta;
    final link = meta.copyWith(color: colors.ink, fontWeight: FontWeight.w600);
    final sentence = l10n.onboardingLegal(_termsMark, _privacyMark);
    final spans = <InlineSpan>[];
    var rest = sentence;
    while (rest.isNotEmpty) {
      final terms = rest.indexOf(_termsMark);
      final privacy = rest.indexOf(_privacyMark);
      final next = [terms, privacy]
          .where((i) => i >= 0)
          .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
      if (next == null) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (next > 0) spans.add(TextSpan(text: rest.substring(0, next)));
      final isTerms = next == terms;
      spans.add(
        TextSpan(
          text: isTerms ? l10n.onboardingTermsLink : l10n.onboardingPrivacyLink,
          style: link,
          recognizer: isTerms ? _terms : _privacy,
        ),
      );
      rest = rest.substring(next + 1);
    }
    return Text.rich(
      TextSpan(
        style: meta.copyWith(color: colors.inkSecondary),
        children: spans,
      ),
      textAlign: TextAlign.center,
    );
  }
}
