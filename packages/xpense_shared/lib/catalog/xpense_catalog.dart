/// Identity of the Xpense A2UI catalog (A2UI_CATALOG 1).
///
/// The catalog itself is `xpense_catalog.json` next to this file, in the A2UI
/// `catalog.json` shape. It is the source of truth: the server loads it with
/// `loadCatalog(ai, id: xpenseCatalogLookupId, file: …)` and the phone's
/// component implementations are checked against it by the parity tests.
library;

/// The catalog's stable URI. It is the `catalogId` of every Xpense surface;
/// it does not need to resolve.
const String xpenseCatalogId =
    'https://bitrelia.com/xpense/a2ui/catalogs/xpense/v1/catalog.json';

/// The id the server registers the catalog under (`a2ui(catalog: 'xpense')`).
const String xpenseCatalogLookupId = 'xpense';

/// The A2UI protocol version of the catalog and of every message built here.
const String xpenseProtocolVersion = '1.0';

/// The catalog file as a package URI, for loaders that resolve one.
const String xpenseCatalogPackageUri =
    'package:xpense_shared/catalog/xpense_catalog.json';

/// The catalog file relative to the `xpense_shared` package root.
const String xpenseCatalogPackagePath = 'lib/catalog/xpense_catalog.json';

/// Every component of the catalog, in catalog order: the 8 basic components,
/// then the 16 Xpense components (A2UI_CATALOG 3).
const List<String> xpenseComponentNames = [
  'Column',
  'Row',
  'List',
  'Text',
  'Divider',
  'Button',
  'TextField',
  'DateTimeInput',
  'EntryList',
  'ChoicePrompt',
  'Transcript',
  'ReceiptSummary',
  'SavedNote',
  'MoneyText',
  'LedgerRow',
  'MiniBars',
  'BreakdownList',
  'TransactionList',
  'BudgetMeter',
  'LoanCard',
  'GoalCard',
  'Nudge',
  'SuggestionChips',
  'Notice',
];

/// The functions kept from the basic catalog (A2UI_CATALOG 4).
const List<String> xpenseFunctionNames = [
  'formatNumber',
  'formatDate',
  'pluralize',
  'required',
  'regex',
  'length',
  'numeric',
  'and',
  'or',
  'not',
];
