import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/accounts/account_form.dart';
import 'package:xpense_app/features/accounts/account_row.dart';
import 'package:xpense_app/features/accounts/accounts_overview.dart';

/// Add accounts (DESIGN_SYSTEM 9, screen 4; artboard 04), onboarding step
/// 3 of 4: "Where does your money live?", the add form, the accounts added
/// so far, and the "Or just say it" example. Each opening balance becomes
/// an `adjustment` entry. Continue goes on to Try it, with or without
/// accounts.
class AddAccountsScreen extends ConsumerWidget {
  /// Creates the screen.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final overview = ref.watch(accountsOverviewProvider).value;
    final rows = overview?.rows ?? const <AccountRow>[];
    return OnboardingFrame(
      topBar: XpTopBar(
        title: l10n.accountsSetupTitle,
        leading: context.canPop() ? const XpBackButton() : null,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepBar(
            current: 3,
            semanticLabel: l10n.onboardingStep(3, onboardingStepCount),
          ),
          const SizedBox(height: XpSpace.s24),
          OnboardingHeading(l10n.accountsSetupHeadline),
          const SizedBox(height: XpSpace.s8),
          OnboardingParagraph(l10n.accountsSetupBody),
          const SizedBox(height: XpSpace.s24),
          const AccountForm.add(inline: true),
          if (rows.isNotEmpty && overview != null) ...[
            const SizedBox(height: XpSpace.s24),
            SectionLabel(l10n.accountsSetupAdded),
            for (final (index, row) in rows.indexed)
              AccountListRow(
                row: row,
                baseCurrency: overview.baseCurrency,
                partnerName: overview.partnerName,
                showDivider: index < rows.length - 1,
              ),
          ],
          const SizedBox(height: XpSpace.s24),
          Text(
            l10n.accountsSetupSayIt,
            style: type.meta.copyWith(color: colors.inkSecondary),
          ),
        ],
      ),
      bottom: XpButton.primary(
        label: l10n.accountsSetupContinue,
        onPressed: () => unawaited(context.push(AppRoutes.tryIt)),
      ),
    );
  }
}
