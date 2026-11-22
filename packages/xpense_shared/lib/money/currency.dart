import 'package:meta/meta.dart';
import 'package:xpense_shared/money/money_failure.dart';
import 'package:xpense_shared/money/result.dart';

/// Version of the exponent table below (DATA_MODEL 1, D-14).
///
/// Stored as `moneySchema` so that a redenomination can be migrated.
const int moneySchemaVersion = 1;

/// The ISO codes of [Currency.values], as a const list for schema enums.
///
/// Kept in step with [Currency] by a test.
const List<String> supportedCurrencyCodes = ['USD', 'IQD'];

/// A currency the app supports, with its app-owned minor-unit exponent.
///
/// The table is explicit and app-owned (DATA_MODEL 1): `USD` has 2 decimals,
/// `IQD` has 0. ISO 4217 lists 3 for IQD, but CLDR lists 0, the smallest note
/// is 250 and no fils circulate, so whole dinars are stored (D-14). An unknown
/// code is a typed failure ([UnknownCurrency]), never a default.
enum Currency {
  /// United States dollar, stored in cents.
  usd('USD', 2),

  /// Iraqi dinar, stored in whole dinars.
  iqd('IQD', 0);

  new(this.code, this.exponent);

  /// The ISO 4217 alphabetic code, for example `USD`.
  final String code;

  /// The number of decimals stored in minor units.
  final int exponent;

  /// Minor units per major unit (`10^exponent`). The only scaling source.
  int get minorPerMajor {
    var factor = 1;
    for (var i = 0; i < exponent; i++) {
      factor *= 10;
    }
    return factor;
  }

  /// The currency for an exact upper-case ISO [code], or `null`.
  static Currency? tryParse(String code) {
    for (final currency in Currency.values) {
      if (currency.code == code) return currency;
    }
    return null;
  }

  /// The currency for an exact upper-case ISO [code], or [UnknownCurrency].
  @useResult
  static Result<Currency, MoneyFailure> parse(String code) {
    final currency = tryParse(code);
    return currency == null ? Err(UnknownCurrency(code)) : Ok(currency);
  }

  @override
  String toString() => code;
}
