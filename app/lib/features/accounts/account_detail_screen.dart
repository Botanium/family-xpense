import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/features/accounts/account_form.dart';
import 'package:xpense_app/features/accounts/account_labels.dart';
import 'package:xpense_app/features/accounts/accounts_overview.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Account detail (DESIGN_SYSTEM 9, screen 11; artboard 11): the balance,
/// the sharing switch on the member's own personal accounts with the
/// "Sharing past entries…" line while the server rewrites the history, and
/// the account's entries. The glass more button edits or archives it.
class AccountDetailScreen extends ConsumerStatefulWidget {
  /// Creates the detail screen of account [accountId].
  const new({required this.accountId, super.key});

  /// The account's id, from the path.
  final String accountId;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  AccountsFailure? _failure;
  bool _busy = false;

  Future<void> _run(
    Future<Result<void, AccountsFailure>> Function(AccountsRepository) call,
  ) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await call(ref.read(accountsRepositoryProvider));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = result.failureOrNull;
    });
  }

  void _more(Account account) {
    final l10n = context.l10n;
    unawaited(
      showXpActionSheet(
        context: context,
        cancelLabel: l10n.accountsCancel,
        actions: [
          XpAction(
            label: l10n.accountsEdit,
            onPressed: () => unawaited(showEditAccountSheet(context, account)),
          ),
          if (account.archived)
            XpAction(
              label: l10n.accountsRestore,
              onPressed: () => unawaited(
                _run((r) => r.setArchived(account.id, archived: false)),
              ),
            )
          else
            XpAction(
              label: l10n.accountsArchive,
              destructive: true,
              onPressed: () => unawaited(
                _run((r) => r.setArchived(account.id, archived: true)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final accounts = ref.watch(accountsProvider);
    final account = accounts.value
        ?.where((a) => a.id == widget.accountId)
        .firstOrNull;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(
              title: l10n.accountsDetailTitle,
              leading: const XpBackButton(),
              trailing: account == null
                  ? null
                  : GlassIconButton(
                      glyph: XpGlyph.more,
                      semanticLabel: l10n.accountsMore,
                      onPressed: _busy ? null : () => _more(account),
                    ),
            ),
            Expanded(
              child: account != null
                  ? _body(context, account)
                  : accounts.isLoading
                  ? const SizedBox.shrink()
                  : Center(child: EmptyState(message: l10n.accountsNotFound)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Account account) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final viewer = ref.watch(accountsRepositoryProvider).viewerUid ?? '';
    final members = ref.watch(householdMembersProvider).value ?? const [];
    final partner = members.where((m) => m.uid != viewer).firstOrNull;
    final partnerName = partner == null || partner.displayName.isEmpty
        ? null
        : partner.displayName;
    final owner = ownerOf(account, viewer);
    final entries = ref.watch(accountEntriesProvider(account.id));
    final failure = switch (_failure) {
      null || AccountsRateNeeded() => null,
      AccountsNotAllowed() => l10n.accountsErrorNotAllowed,
      AccountNotFound() => l10n.accountsErrorNotFound,
      AccountsUnknown() => l10n.accountsErrorUnknown,
    };

    return ListView(
      padding: EdgeInsetsDirectional.only(
        start: XpSpace.screenMargin,
        end: XpSpace.screenMargin,
        top: XpSpace.s8,
        bottom: XpSpace.bottomControlOffset(context),
      ),
      children: [
        Text(
          l10n.accountsDetailHeader(
            account.name,
            l10n.accountOwnerTag(owner, partnerName),
          ),
          style: type.subhead.copyWith(color: colors.inkSecondary),
        ),
        const SizedBox(height: XpSpace.s4),
        MoneyText(
          account.balanceMinor,
          exponent: account.currency.exponent,
          currency: account.currency.code,
          style: MoneyStyle.medium,
        ),
        const SizedBox(height: XpSpace.s4),
        Text(
          l10n.accountKindName(account.kind).toUpperCase(),
          style: type.monoLabel.copyWith(color: colors.inkSecondary),
        ),
        if (account.archived) ...[
          const SizedBox(height: XpSpace.s8),
          Text(
            l10n.accountsArchived,
            style: type.meta.copyWith(color: colors.inkSecondary),
          ),
        ],
        const SizedBox(height: XpSpace.s24),
        if (account.isOwnedBy(viewer))
          _SharingSwitch(
            account: account,
            partnerName: partnerName,
            hasPartner: partner != null,
            busy: _busy,
            onChanged: (shared) =>
                unawaited(_run((r) => r.setShared(account.id, shared: shared))),
          ),
        if (account.sharingInProgress) ...[
          const SizedBox(height: XpSpace.s8),
          _SharingProgress(account: account),
        ],
        if (failure != null) ...[
          const SizedBox(height: XpSpace.s8),
          Semantics(
            liveRegion: true,
            child: Text(
              failure,
              style: type.meta.copyWith(color: colors.danger),
            ),
          ),
        ],
        const SizedBox(height: XpSpace.s12),
        const Hairline(),
        const SizedBox(height: XpSpace.s16),
        SectionLabel(l10n.accountsEntries),
        ...switch (entries) {
          AsyncData(:final value) when value.isEmpty => [
            Padding(
              padding: const EdgeInsetsDirectional.only(top: XpSpace.s16),
              child: Text(
                l10n.accountsEntriesEmpty,
                style: type.meta.copyWith(color: colors.inkSecondary),
              ),
            ),
          ],
          AsyncData(:final value) => [
            for (final entry in value) _EntryRow(entry: entry),
          ],
          _ => [const Skeleton()],
        },
      ],
    );
  }
}

/// "Share with Sam" with its line underneath and the switch.
class _SharingSwitch extends StatelessWidget {
  const new({
    required this.account,
    required this.partnerName,
    required this.hasPartner,
    required this.busy,
    required this.onChanged,
  });

  final Account account;
  final String? partnerName;
  final bool hasPartner;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final name = partnerName;
    final title = name == null
        ? l10n.accountsShareWithPartner
        : l10n.accountsShareWith(name);
    final line = !hasPartner
        ? l10n.accountsShareNoPartner
        : account.sharedWithPartner
        ? (name == null
              ? l10n.accountsShareOnUnnamed
              : l10n.accountsShareOn(name))
        : l10n.accountsShareOff;
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: type.bodyStrong),
                Text(
                  line,
                  style: type.meta.copyWith(color: colors.inkSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: XpSpace.s12),
          XpSwitch(
            value: account.sharedWithPartner,
            semanticLabel: title,
            onChanged: hasPartner && !busy ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

/// The spinner and "Sharing past entries… 18 of 42" line.
class _SharingProgress extends StatelessWidget {
  const new({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final done = account.sharingDone;
    final total = account.sharingTotal;
    final counted = done != null && total != null && total > 0;
    final text = account.sharedWithPartner
        ? counted
              ? l10n.accountsSharingProgress(done, total)
              : l10n.accountsSharingStarted
        : counted
        ? l10n.accountsUnsharingProgress(done, total)
        : l10n.accountsUnsharingStarted;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          const ExcludeSemantics(child: XpSpinner()),
          const SizedBox(width: XpSpace.s8),
          Expanded(
            child: Text(
              text,
              style: type.meta.copyWith(color: colors.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry: title, date and kind, signed amount (income in green).
class _EntryRow extends StatelessWidget {
  const new({required this.entry});

  final AccountEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = DateFormat.MMMd(locale).format(entry.occurredAt.toLocal());
    return XpListRow(
      title: entry.title.isNotEmpty
          ? entry.title
          : entry.type == 'adjustment'
          ? l10n.accountsOpeningEntry
          : l10n.entryTypeName(entry.type),
      subtitle: l10n.accountsEntryMeta(date, l10n.entryTypeName(entry.type)),
      trailing: MoneyText(
        entry.amountMinor,
        exponent: entry.currency.exponent,
        tone: entry.amountMinor > 0 && entry.type == 'income'
            ? MoneyTone.income
            : MoneyTone.neutral,
        signed: true,
        textAlign: TextAlign.end,
      ),
    );
  }
}
