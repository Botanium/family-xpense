import 'package:xpense_app/core/l10n/generated/app_localizations.dart';
import 'package:xpense_app/data/transactions_repository.dart';
import 'package:xpense_app/features/capture/manual/manual_entry.dart';

/// The words of the Add manually sheet for its enums and failures.
extension ManualLabels on AppLocalizations {
  /// The type tab's label.
  String manualKindTab(ManualKind kind) => switch (kind) {
    ManualKind.expense => captureManualTabExpense,
    ManualKind.income => captureManualTabIncome,
    ManualKind.transfer => captureManualTabTransfer,
    ManualKind.loan => captureManualTabLoan,
  };

  /// The bottom button's label.
  String manualSaveLabel(ManualKind kind, {required bool editing}) => editing
      ? captureManualSaveChanges
      : switch (kind) {
          ManualKind.expense => captureManualSaveExpense,
          ManualKind.income => captureManualSaveIncome,
          ManualKind.transfer => captureManualSaveTransfer,
          ManualKind.loan => captureManualSaveLoan,
        };

  /// A loan direction chip's label.
  String loanDirectionChip(LoanDirection direction) => switch (direction) {
    LoanDirection.lent => captureManualLoanLent,
    LoanDirection.borrowed => captureManualLoanBorrowed,
    LoanDirection.paidBack => captureManualLoanPaidBack,
    LoanDirection.repaid => captureManualLoanRepaid,
  };

  /// The error shown next to [field].
  String manualError(ManualField field, ManualIssue issue, String currency) =>
      switch ((field, issue)) {
        (ManualField.amount || ManualField.toAmount, ManualIssue.missing) =>
          captureManualErrorAmountMissing,
        (ManualField.amount || ManualField.toAmount, ManualIssue.invalid) =>
          captureManualErrorAmountInvalid(currency),
        (_, ManualIssue.outOfRange) => captureManualErrorAmountRange,
        (ManualField.account, ManualIssue.missing) =>
          captureManualErrorAccountMissing,
        (ManualField.toAccount, ManualIssue.missing) =>
          captureManualErrorToAccountMissing,
        (_, ManualIssue.sameAccount) => captureManualErrorSameAccount,
        (_, ManualIssue.unknown) => captureManualErrorUnknown,
        (ManualField.category, ManualIssue.missing) =>
          captureManualErrorCategoryMissing,
        (_, ManualIssue.wrongKind) => captureManualErrorWrongKind,
        (ManualField.person, ManualIssue.missing) =>
          captureManualErrorPersonMissing,
        (_, ManualIssue.tooLong) => captureManualErrorTooLong,
        (_, ManualIssue.noPartner) => captureManualErrorNoPartner,
        (_, ManualIssue.currencyMismatch) => captureManualErrorCurrencyMismatch,
        (_, ManualIssue.rateNeeded) => captureManualErrorRateNeeded,
        (_, ManualIssue.missing || ManualIssue.invalid) =>
          captureManualErrorInvalid,
      };

  /// The toast for a failure that is not about one field.
  String manualFailure(TransactionsFailure failure) => switch (failure) {
    TransactionsNotAllowed() => captureManualFailNotAllowed,
    TooManyEntries() => captureManualFailTooMany,
    TransactionNotFound() => captureManualFailNotFound,
    TransactionDeleted() => captureManualFailDeleted,
    TransactionConflict() => captureManualFailConflict,
    EntryInvalid() ||
    EntryRateNeeded() ||
    TransactionNotDeleted() ||
    TransactionsUnknown() => captureManualFailUnknown,
  };
}
