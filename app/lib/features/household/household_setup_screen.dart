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
import 'package:xpense_app/features/household/household_setup_view_model.dart';
import 'package:xpense_app/features/household/invite_share.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Household setup (DESIGN_SYSTEM 9, screen 3; artboard 03; PRD ON-3,
/// ON-4): household name, the person's own name, the base currency with
/// USD preselected, then the invite code with Share.
///
/// The code exists only once the household does, so the screen has two
/// steps: Continue creates the household from the form, then the fields
/// turn read-only and the invite appears under them, as on the artboard.
/// The second Continue (or Invite later) goes to the next onboarding step.
class HouseholdSetupScreen extends ConsumerStatefulWidget {
  /// Creates household setup.
  const new({super.key});

  @override
  ConsumerState<HouseholdSetupScreen> createState() =>
      _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends ConsumerState<HouseholdSetupScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _displayName = TextEditingController();

  HouseholdSetupViewModel get _viewModel =>
      ref.read(householdSetupViewModelProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Apple and Google may have given a name; it is only a suggestion.
    _displayName.text =
        ref.read(authRepositoryProvider).currentUser?.displayName ?? '';
    _fill(ref.read(householdSetupViewModelProvider).household);
  }

  @override
  void dispose() {
    _name.dispose();
    _displayName.dispose();
    super.dispose();
  }

  /// Shows what the household holds once it exists.
  void _fill(HouseholdSummary? household) {
    if (household == null) return;
    _name.text = household.name;
    final mine = household.myDisplayName;
    if (mine != null) _displayName.text = mine;
  }

  void _create() => unawaited(
    _viewModel.create(name: _name.text, displayName: _displayName.text),
  );

  void _retry() => unawaited(
    _viewModel.retry(name: _name.text, displayName: _displayName.text),
  );

  void _share(HouseholdInvite invite) {
    final message = context.l10n.householdInviteShareMessage(
      invite.displayCode,
      invite.link,
    );
    unawaited(ref.read(shareTextProvider)(message));
    _viewModel.markShared();
  }

  void _next() => unawaited(context.push(AppRoutes.tryIt));

  @override
  Widget build(BuildContext context) {
    ref.listen(
      householdSetupViewModelProvider.select((s) => s.household),
      (_, household) => _fill(household),
    );
    final l10n = context.l10n;
    final state = ref.watch(householdSetupViewModelProvider);
    final failure = state.failure;
    final message = failure == null || failure is HouseholdOffline
        ? null
        : householdFailureMessage(l10n, failure);
    final invite = state.invite;
    return OnboardingFrame(
      topBar: XpTopBar(
        title: l10n.householdSetupTitle,
        leading: context.canPop() ? const XpBackButton() : null,
      ),
      banner: state.offline
          ? OfflineBanner(
              message: l10n.householdOffline,
              actionLabel: l10n.householdRetry,
              onAction: state.creating ? null : _retry,
            )
          : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepBar(
            current: 2,
            semanticLabel: l10n.onboardingStep(2, onboardingStepCount),
          ),
          const SizedBox(height: XpSpace.s24),
          OnboardingHeading(l10n.householdSetupHeadline),
          const SizedBox(height: XpSpace.s24),
          XpTextField(
            label: l10n.householdNameLabel,
            controller: _name,
            hint: l10n.householdNameHint,
            textInputAction: TextInputAction.next,
            enabled: state.editable,
            error: nameProblemMessage(l10n, state.nameProblem),
            onChanged: (_) => _viewModel.nameEdited(),
          ),
          const SizedBox(height: XpSpace.s16),
          XpTextField(
            label: l10n.householdYourNameLabel,
            controller: _displayName,
            hint: l10n.householdYourNameHint,
            autofillHints: const [AutofillHints.givenName],
            textInputAction: TextInputAction.done,
            enabled: state.editable,
            error: nameProblemMessage(
              l10n,
              state.displayNameProblem,
              empty: l10n.householdYourNameErrorEmpty,
            ),
            onChanged: (_) => _viewModel.displayNameEdited(),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: XpSpace.s24),
          SectionLabel(l10n.householdCurrencyLabel),
          const SizedBox(height: XpSpace.s8),
          ChoiceChips<Currency>(
            options: [
              for (final currency in Currency.values)
                ChoiceOption(value: currency, label: currency.code),
            ],
            selected: state.currency,
            onSelected: state.editable ? _viewModel.selectCurrency : null,
          ),
          if (!state.created) ...[
            const SizedBox(height: XpSpace.s8),
            OnboardingMessage.note(l10n.householdCurrencyNote),
          ],
          if (invite != null) ...[
            const SizedBox(height: XpSpace.s24),
            SectionLabel(l10n.householdInviteLabel),
            const SizedBox(height: XpSpace.s8),
            _InviteCode(
              status: invite,
              onShare: _share,
              onRetry: _viewModel.requestInvite,
            ),
          ],
          const SizedBox(height: XpSpace.s12),
          LedgerRow(
            label: l10n.householdSharedLabel,
            value: l10n.householdSharedValue,
          ),
          LedgerRow(
            label: l10n.householdPrivateLabel,
            value: l10n.householdPrivateValue,
          ),
          if (message != null) ...[
            const SizedBox(height: XpSpace.s16),
            OnboardingMessage.error(message),
          ],
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.created)
            XpButton.primary(label: l10n.householdContinue, onPressed: _next)
          else
            XpButton.primary(
              label: state.creating
                  ? l10n.householdCreating
                  : l10n.householdCreateAction,
              onPressed: state.editable ? _create : null,
            ),
          const SizedBox(height: XpSpace.s8),
          if (!state.created)
            XpButton.text(
              label: l10n.householdHaveInvite,
              expand: true,
              onPressed: state.editable
                  ? () => unawaited(context.push(AppRoutes.join))
                  : null,
            )
          else
            // Once the code is shared (or the partner is in) there is
            // nothing to put off; the slot keeps its height so Continue
            // does not jump.
            Visibility(
              visible: !state.shared && invite is! InviteNotNeeded,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: XpButton.text(
                label: l10n.householdInviteLater,
                expand: true,
                onPressed: _next,
              ),
            ),
        ],
      ),
    );
  }
}

/// The invite code in mono with Share (artboard 03), or what stands in for
/// it while it is made, when it failed, or once the partner has joined.
class _InviteCode extends StatelessWidget {
  const new({
    required this.status,
    required this.onShare,
    required this.onRetry,
  });

  final InviteStatus status;
  final ValueChanged<HouseholdInvite> onShare;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return switch (status) {
      InviteLoading() => Align(
        alignment: AlignmentDirectional.centerStart,
        child: XpSpinner(semanticLabel: l10n.householdInviteLoading),
      ),
      InviteReady(:final invite) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // At large text sizes Share moves under the code instead of
          // squeezing it.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: XpSpace.s16,
            runSpacing: XpSpace.s8,
            children: [
              Semantics(
                label: l10n.householdInviteCodeSemantics(
                  invite.code.split('').join(' '),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    invite.displayCode,
                    style: XpType.of(context).figureMedium,
                  ),
                ),
              ),
              XpButton.secondary(
                label: l10n.householdInviteShare,
                expand: false,
                onPressed: () => onShare(invite),
              ),
            ],
          ),
          const SizedBox(height: XpSpace.s8),
          OnboardingMessage.note(l10n.householdInviteValidity),
        ],
      ),
      InviteFailed(:final failure) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingMessage.error(inviteFailureMessage(l10n, failure)),
          XpButton.text(
            label: l10n.householdRetry,
            onPressed: () => unawaited(onRetry()),
          ),
        ],
      ),
      InviteNotNeeded() => OnboardingMessage.note(l10n.householdInviteFull),
    };
  }
}
