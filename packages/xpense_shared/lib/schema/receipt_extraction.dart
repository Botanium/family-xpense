import 'package:schemantic/schemantic.dart';
import 'package:xpense_shared/money/currency.dart';

part 'receipt_extraction.g.dart';

/// Structured output of `receipt_lines.prompt` (AI_PIPELINE 8):
/// merchant, date, currency, total and line items.
@Schema(description: 'Merchant, date, total and line items of a receipt.')
abstract class $ReceiptExtraction {
  /// The merchant name as printed.
  String? get merchant;

  /// The receipt date, `YYYY-MM-DD`.
  @StringField(description: 'Receipt date, YYYY-MM-DD.')
  String? get date;

  /// ISO currency code of the amounts.
  @StringField(enumValues: supportedCurrencyCodes)
  String? get currency;

  /// The printed total in minor units of [currency].
  @IntegerField(description: 'Total in minor units of currency.', minimum: 0)
  int? get totalMinor;

  /// The line items, in printed order.
  List<$ReceiptLine>? get lines;
}

/// One line item of a receipt.
@Schema(description: 'One line item of a receipt.')
abstract class $ReceiptLine {
  /// The line text as printed.
  String get text;

  /// The line amount in minor units of the receipt currency.
  @IntegerField(description: 'Line amount in minor units of currency.')
  int get amountMinor;

  /// A suggested category slug or id.
  String? get categoryId;
}
