import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/features/accounts/account_form.dart';
import 'package:xpense_app/features/accounts/account_row.dart';
import 'package:xpense_app/features/accounts/accounts_overview.dart';

/// Accounts (DESIGN_SYSTEM 9, screen 10; artboard 10): the total of what
/// the member can see, the filter bar (All, Mine, Partner, Joint) and the
/// account rows; the glass plus button adds one.
class AccountsScreen extends ConsumerStatefulWidget {
  /// Creates Accounts.
  const new({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  AccountsFilter _filter = AccountsFilter.all;
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final overview = ref.watch(accountsOverviewProvider);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(
              title: l10n.accountsTitle,
              trailing: GlassIconButton(
                glyph: XpGlyph.plus,
                semanticLabel: l10n.accountsAdd,
                onPressed: () => unawaited(showAddAccountSheet(context)),
              ),
            ),
            Expanded(
              child: switch (overview) {
                AsyncData(:final value) => _list(context, value),
                AsyncError() => Center(
                  child: EmptyState(
                    message: l10n.accountsLoadError,
                    actionLabel: l10n.accountsRetry,
                    onAction: () => ref.invalidate(accountsProvider),
                  ),
                ),
                _ => Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: XpSpace.screenMargin,
                  ),
                  child: Skeleton(rows: 5, semanticLabel: l10n.accountsTitle),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, AccountsOverview overview) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final filters = [
      AccountsFilter.all,
      AccountsFilter.mine,
      if (overview.hasPartner) AccountsFilter.partner,
      AccountsFilter.joint,
    ];
    if (!filters.contains(_filter)) _filter = AccountsFilter.all;
    final rows = overview.filtered(_filter);
    final archived = ref
        .watch(accountsProvider)
        .value
        ?.where((a) => a.archived)
        .toList();
    final base = overview.baseCurrency;
    final partner = overview.partnerName;
    final notes = [
      if (!overview.complete && partner == null)
        l10n.accountsYourViewNoteUnnamed
      else if (!overview.complete)
        l10n.accountsYourViewNote(partner!),
      for (final currency in overview.unconverted)
        l10n.accountsUnconvertedNote(currency.code),
    ];

    return ListView(
      padding: EdgeInsetsDirectional.only(
        start: XpSpace.screenMargin,
        end: XpSpace.screenMargin,
        top: XpSpace.s8,
        bottom: XpSpace.contentBottomPadding(context),
      ),
      children: [
        Text(
          overview.complete
              ? l10n.accountsHouseholdBalance
              : l10n.accountsYourView,
          style: type.subhead.copyWith(color: colors.inkSecondary),
        ),
        const SizedBox(height: XpSpace.s4),
        MoneyText(
          overview.totalMinor,
          exponent: base.exponent,
          currency: base.code,
          style: MoneyStyle.medium,
        ),
        for (final note in notes) ...[
          const SizedBox(height: XpSpace.s4),
          Text(note, style: type.meta.copyWith(color: colors.inkSecondary)),
        ],
        const SizedBox(height: XpSpace.s24),
        Semantics(
          label: l10n.accountsFilterLabel,
          container: true,
          child: XpFilterBar(
            labels: [
              for (final filter in filters)
                switch (filter) {
                  AccountsFilter.all => l10n.accountsFilterAll,
                  AccountsFilter.mine => l10n.accountsFilterMine,
                  AccountsFilter.partner =>
                    partner ?? l10n.accountsFilterPartner,
                  AccountsFilter.joint => l10n.accountsFilterJoint,
                },
            ],
            selectedIndex: filters.indexOf(_filter),
            onSelected: (index) => setState(() => _filter = filters[index]),
          ),
        ),
        const SizedBox(height: XpSpace.s8),
        if (overview.rows.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: XpSpace.s32),
            child: EmptyState(
              message: l10n.accountsEmpty,
              actionLabel: l10n.accountsAdd,
              onAction: () => unawaited(showAddAccountSheet(context)),
            ),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: XpSpace.s32),
            child: EmptyState(message: l10n.accountsFilterEmpty),
          ),
        for (final row in rows)
          AccountListRow(
            row: row,
            baseCurrency: base,
            partnerName: partner,
            onTap: () =>
                unawaited(context.push(AppRoutes.account(row.account.id))),
          ),
        if (archived != null && archived.isNotEmpty) ...[
          const SizedBox(height: XpSpace.s16),
          XpButton.text(
            label: _showArchived
                ? l10n.accountsArchivedHide
                : l10n.accountsArchivedShow(archived.length),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
          if (_showArchived)
            for (final account in archived)
              AccountListRow(
                row: AccountRow(
                  account: account,
                  owner: ownerOf(
                    account,
                    ref.read(accountsRepositoryProvider).viewerUid ?? '',
                  ),
                ),
                baseCurrency: base,
                partnerName: partner,
                onTap: () =>
                    unawaited(context.push(AppRoutes.account(account.id))),
              ),
        ],
      ],
    );
  }
}
