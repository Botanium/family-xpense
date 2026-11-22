import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/features/household/household_messages.dart';
import 'package:xpense_app/features/household/join_view_model.dart';

/// Joining a partner's household (PRD ON-4, BACKLOG S1.5): the invite code,
/// filled in from an `xpense://join?code=…` link or typed ("I have an
/// invite"), and the name the partner will see.
///
/// No artboard exists for it; it follows household setup's frame. After a
/// join it shows a welcome line and Continue to the next onboarding step.
class JoinScreen extends ConsumerStatefulWidget {
  /// Creates the join screen, with [initialCode] from a link.
  const new({this.initialCode, super.key});

  /// The code a link carried, already upper-cased without separators.
  final String? initialCode;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _displayName = TextEditingController();

  JoinViewModel get _viewModel => ref.read(joinViewModelProvider.notifier);

  @override
  void initState() {
    super.initState();
    _code.text = formatInviteCode(widget.initialCode ?? '');
    _displayName.text =
        ref.read(authRepositoryProvider).currentUser?.displayName ?? '';
  }

  @override
  void dispose() {
    _code.dispose();
    _displayName.dispose();
    super.dispose();
  }

  void _submit() => unawaited(
    _viewModel.submit(code: _code.text, displayName: _displayName.text),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(joinViewModelProvider);
    final joined = state.joined;
    return OnboardingFrame(
      topBar: XpTopBar(
        title: l10n.householdJoinTitle,
        leading: context.canPop() && joined == null
            ? const XpBackButton()
            : null,
      ),
      banner: state.offline
          ? OfflineBanner(
              message: l10n.householdJoinOffline,
              actionLabel: l10n.householdRetry,
              onAction: state.busy ? null : _submit,
            )
          : null,
      content: joined == null
          ? _form(context, state)
          : _welcome(context, joined),
      bottom: joined == null
          ? null
          : XpButton.primary(
              label: l10n.householdContinue,
              onPressed: () => unawaited(context.push(AppRoutes.tryIt)),
            ),
    );
  }

  Widget _form(BuildContext context, JoinState state) {
    final l10n = context.l10n;
    final failure = state.failure;
    final message = failure == null || failure is HouseholdOffline
        ? null
        : householdFailureMessage(l10n, failure);
    final householdless = switch (ref.watch(membershipProvider).value) {
      NoHousehold() => true,
      _ => false,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepBar(
          current: 2,
          semanticLabel: l10n.onboardingStep(2, onboardingStepCount),
        ),
        const SizedBox(height: XpSpace.s24),
        OnboardingHeading(l10n.householdJoinHeadline),
        const SizedBox(height: XpSpace.s8),
        OnboardingParagraph(l10n.householdJoinBody),
        const SizedBox(height: XpSpace.s32),
        XpTextField(
          label: l10n.householdJoinCodeLabel,
          controller: _code,
          hint: l10n.householdJoinCodeHint,
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.next,
          enabled: state.editable,
          error: codeProblemMessage(l10n, state.codeProblem),
          onChanged: (_) => _viewModel.codeEdited(),
        ),
        const SizedBox(height: XpSpace.s24),
        XpTextField(
          label: l10n.householdYourNameLabel,
          controller: _displayName,
          hint: l10n.householdYourNameHint,
          autofillHints: const [AutofillHints.givenName],
          textInputAction: TextInputAction.done,
          enabled: state.editable,
          error: nameProblemMessage(
            l10n,
            state.nameProblem,
            empty: l10n.householdYourNameErrorEmpty,
          ),
          onChanged: (_) => _viewModel.nameEdited(),
          onSubmitted: (_) => _submit(),
        ),
        if (message != null) ...[
          const SizedBox(height: XpSpace.s16),
          OnboardingMessage.error(message),
        ],
        const SizedBox(height: XpSpace.s32),
        XpButton.primary(
          label: state.busy ? l10n.householdJoining : l10n.householdJoinAction,
          onPressed: state.editable ? _submit : null,
        ),
        if (householdless) ...[
          const SizedBox(height: XpSpace.s8),
          XpButton.text(
            label: l10n.householdJoinSetUpInstead,
            expand: true,
            onPressed: state.editable
                ? () => context.go(AppRoutes.householdSetup)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _welcome(BuildContext context, JoinedHousehold joined) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepBar(
          current: 2,
          semanticLabel: l10n.onboardingStep(2, onboardingStepCount),
        ),
        const SizedBox(height: XpSpace.s24),
        OnboardingHeading(
          joined.name.isEmpty
              ? l10n.householdJoinedHeadlineUnnamed
              : l10n.householdJoinedHeadline(joined.name),
        ),
        const SizedBox(height: XpSpace.s8),
        OnboardingParagraph(l10n.householdJoinedBody),
        const SizedBox(height: XpSpace.s24),
        LedgerRow(
          label: l10n.householdSharedLabel,
          value: l10n.householdSharedValue,
        ),
        LedgerRow(
          label: l10n.householdPrivateLabel,
          value: l10n.householdPrivateValue,
        ),
      ],
    );
  }
}
