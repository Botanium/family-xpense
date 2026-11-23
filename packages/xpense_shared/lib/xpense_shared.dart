/// Pure Dart core shared by the Family Xpense app and server.
///
/// Money and FX, digit folding, the fast parser, schemantic schemas, the
/// intent taxonomy, the catalog JSON and the local surface builder live here
/// (ARCHITECTURE 2). This library must not depend on Flutter, `dart:io`,
/// Firebase or `a2ui_core`, so that the app and the server can each resolve
/// their own `a2ui_core` (D-05). The modules are added from WP-02 on.
library;

export 'catalog/xpense_catalog.dart';
export 'ledger/balance_effects.dart';
export 'ledger/uuid_v7.dart';
export 'money/allocate.dart';
export 'money/currency.dart';
export 'money/fx.dart';
export 'money/money.dart';
export 'money/money_failure.dart';
export 'money/result.dart';
export 'parse/amounts.dart';
export 'parse/dates.dart';
export 'parse/fast_parser.dart';
export 'parse/hints.dart';
export 'parse/lexicon.dart';
export 'parse/normalize.dart';
export 'parse/numbers.dart';
export 'parse/receipt.dart';
export 'parse/rules.dart';
export 'parse/signals.dart';
export 'parse/tokens.dart';
export 'routing/capture_router.dart';
export 'schema/decide.dart';
export 'schema/entry_draft.dart';
export 'schema/parse_result.dart';
export 'schema/receipt_extraction.dart';
export 'schema/wire_values.dart';
export 'surface/draft_checks.dart';
export 'surface/local_surfaces.dart';
export 'surface/receipt_groups.dart';
export 'surface/surface_builder.dart';
export 'taxonomy/categories.dart';
export 'taxonomy/intents.dart';
