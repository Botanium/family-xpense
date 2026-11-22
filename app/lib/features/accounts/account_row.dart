import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/accounts/account_labels.dart';
import 'package:xpense_app/features/accounts/accounts_overview.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// One account in a list (artboards 04 and 10): mono kind tag, name, kind
/// and owner, the balance in mono, and the converted balance under an
/// account in another currency.
class AccountListRow extends StatelessWidget {
  /// Creates a row.
  const new({
    required this.row,
    required this.baseCurrency,
    this.partnerName,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  /// The account and whose it is.
  final AccountRow row;

  /// The household base currency: balances in it show no code.
  final Currency baseCurrency;

  /// The partner's name for owner tags.
  final String? partnerName;

  /// Opens the account.
  final VoidCallback? onTap;

  /// Whether to draw the hairline under the row.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final account = row.account;
    final inBase = account.currency == baseCurrency;
    final meta = l10n.accountsRowMeta(
      l10n.accountKindName(account.kind),
      l10n.accountOwnerTag(row.owner, partnerName),
    );
    final baseMinor = row.baseMinor;
    return XpListRow(
      title: account.name,
      subtitle: account.sharingInProgress
          ? '$meta · ${l10n.accountsSharing}'
          : meta,
      onTap: onTap,
      showDivider: showDivider,
      leading: SizedBox(
        width: XpSpace.s40,
        child: ExcludeSemantics(
          child: Text(
            l10n.accountKindTag(account.kind),
            style: type.monoLabel.copyWith(color: colors.inkSecondary),
          ),
        ),
      ),
      trailing: MoneyText(
        account.balanceMinor,
        exponent: account.currency.exponent,
        currency: inBase ? '' : account.currency.code,
        textAlign: TextAlign.end,
        converted: baseMinor == null
            ? null
            : l10n.accountsApprox(
                MoneyFormat.figure(
                  baseMinor,
                  exponent: baseCurrency.exponent,
                ).amount,
              ),
      ),
    );
  }
}
