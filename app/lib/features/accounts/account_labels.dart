import 'package:xpense_app/core/l10n/generated/app_localizations.dart';
import 'package:xpense_app/data/accounts_repository.dart';
import 'package:xpense_app/features/accounts/accounts_overview.dart';

/// The words the Accounts screens use for kinds, owners and entry types.
extension AccountLabels on AppLocalizations {
  /// The kind's name, such as "Bank account".
  String accountKindName(AccountKind kind) => switch (kind) {
    AccountKind.cash => accountsKindCash,
    AccountKind.bank => accountsKindBank,
    AccountKind.credit => accountsKindCredit,
    AccountKind.savings => accountsKindSavings,
    AccountKind.other => accountsKindOther,
  };

  /// The kind's chip label, such as "Bank".
  String accountKindChip(AccountKind kind) => switch (kind) {
    AccountKind.cash => accountsChipCash,
    AccountKind.bank => accountsChipBank,
    AccountKind.credit => accountsChipCredit,
    AccountKind.savings => accountsChipSavings,
    AccountKind.other => accountsChipOther,
  };

  /// The mono abbreviation at the start of a row, such as "BANK".
  String accountKindTag(AccountKind kind) => switch (kind) {
    AccountKind.cash => accountsTagCash,
    AccountKind.bank => accountsTagBank,
    AccountKind.credit => accountsTagCredit,
    AccountKind.savings => accountsTagSavings,
    AccountKind.other => accountsTagOther,
  };

  /// Whose the account is, such as "You" or "Sam, shared".
  String accountOwnerTag(AccountOwner owner, String? partnerName) =>
      switch (owner) {
        AccountOwner.mine => accountsOwnerYou,
        AccountOwner.mineShared => accountsOwnerYouShared,
        AccountOwner.partner =>
          partnerName == null
              ? accountsOwnerPartnerUnnamed
              : accountsOwnerPartner(partnerName),
        AccountOwner.joint => accountsOwnerJoint,
      };

  /// A ledger type's name, such as "Income".
  String entryTypeName(String type) => switch (type) {
    'expense' => accountsTypeExpense,
    'income' => accountsTypeIncome,
    'transfer' => accountsTypeTransfer,
    'loan_given' || 'loan_taken' => accountsTypeLoan,
    'repayment_received' || 'repayment_made' => accountsTypeRepayment,
    _ => accountsTypeAdjustment,
  };
}
