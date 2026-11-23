/// Registers the agent tools (AI_PIPELINE 8).
///
/// Every tool reads the household and member from the verified request
/// context (`XpenseContext.of(ctx.context)`), never from its arguments, so
/// the model cannot point a tool at another household. All tools are
/// read-only; `prepareEntries` writes nothing at all (the phone is the only
/// writer of entries, D-10).
library;

import 'package:genkit/genkit.dart';
import 'package:logging/logging.dart';

import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/ledger_tools.dart';
import 'package:xpense_agent/tools/prepare_entries.dart';
import 'package:xpense_agent/tools/schemas.dart';
import 'package:xpense_agent/tools/tool_deps.dart';

final _log = Logger('xpense.tools');

/// The tool names, as the prompt lists them.
abstract final class XpenseToolNames {
  /// `prepareEntries`.
  static const prepareEntries = 'prepareEntries';

  /// `queryLedger`.
  static const queryLedger = 'queryLedger';

  /// `getBalances`.
  static const getBalances = 'getBalances';

  /// `getBudgets`.
  static const getBudgets = 'getBudgets';

  /// `findLoans`.
  static const findLoans = 'findLoans';

  /// `getFxRate`.
  static const getFxRate = 'getFxRate';

  /// `findEntries`.
  static const findEntries = 'findEntries';

  /// Every tool.
  static const List<String> all = [
    prepareEntries,
    queryLedger,
    getBalances,
    getBudgets,
    findLoans,
    getFxRate,
    findEntries,
  ];
}

/// Defines every agent tool on [ai].
List<Tool<dynamic, dynamic>> defineXpenseTools(
  Genkit ai,
  ToolDeps deps,
) => <Tool<dynamic, dynamic>>[
  ai.defineTool<PrepareEntriesInput, PrepareEntriesOutput>(
    name: XpenseToolNames.prepareEntries,
    description:
        'Turns every money event of the message into checked drafts. Call it '
        'once with all entries before rendering any EntryList; calling again '
        'replaces the whole set. Render its drafts unchanged.',
    inputSchema: PrepareEntriesInput.$schema,
    outputSchema: PrepareEntriesOutput.$schema,
    fn: (input, ctx) => _run(
      XpenseToolNames.prepareEntries,
      ctx.context,
      (c) => prepareEntries(input, c, deps),
    ),
  ),
  ai.defineTool<LedgerQuery, LedgerResult>(
    name: XpenseToolNames.queryLedger,
    description:
        'Totals, counts or averages of saved entries the member can see, '
        'grouped by day, week, month, category, account or who. Amounts are '
        'integer minor units in the household base currency.',
    inputSchema: LedgerQuery.$schema,
    outputSchema: LedgerResult.$schema,
    fn: (input, ctx) => _run(
      XpenseToolNames.queryLedger,
      ctx.context,
      (c) => queryLedger(input, c, deps),
    ),
  ),
  ai.defineTool<BalancesQuery, BalancesResult>(
    name: XpenseToolNames.getBalances,
    description: 'Account balances and the household total.',
    inputSchema: BalancesQuery.$schema,
    outputSchema: BalancesResult.$schema,
    fn: (input, ctx) => _run(
      XpenseToolNames.getBalances,
      ctx.context,
      (c) => getBalances(input, c, deps),
    ),
  ),
  ai.defineTool<BudgetsQuery, BudgetsResult>(
    name: XpenseToolNames.getBudgets,
    description: 'Budgets for a month with spent and remaining.',
    inputSchema: BudgetsQuery.$schema,
    outputSchema: BudgetsResult.$schema,
    fn: (input, ctx) => _run(
      XpenseToolNames.getBudgets,
      ctx.context,
      (c) => getBudgets(input, c, deps),
    ),
  ),
  ai.defineTool<LoansQuery, LoansResult>(
    name: XpenseToolNames.findLoans,
    description: 'Loans and debts with outstanding amounts and due dates.',
    inputSchema: LoansQuery.$schema,
    outputSchema: LoansResult.$schema,
    fn: (input, ctx) => _run(
      XpenseToolNames.findLoans,
      ctx.context,
      (c) => findLoans(input, c, deps),
    ),
  ),
  ai.defineTool<FxRateQuery, FxRateResult>(
    name: XpenseToolNames.getFxRate,
    description: "The household's USD/IQD rate for a day.",
    inputSchema: FxRateQuery.$schema,
    outputSchema: FxRateResult.$schema,
    fn: (input, ctx) => _run(
      XpenseToolNames.getFxRate,
      ctx.context,
      (c) => getFxRate(input, c, deps),
    ),
  ),
  ai.defineTool<FindEntriesQuery, FoundEntries>(
    name: XpenseToolNames.findEntries,
    description:
        'Finds up to 10 saved entries by words, dates or amount, newest '
        'first, shaped for TransactionList.',
    inputSchema: FindEntriesQuery.$schema,
    outputSchema: FoundEntries.$schema,
    fn: (input, ctx) => _run(
      XpenseToolNames.findEntries,
      ctx.context,
      (c) => findEntries(input, c, deps),
    ),
  ),
];

/// Runs one tool body with the verified context. A missing context is
/// refused (`missing_context`); an unreachable backend becomes an
/// `unavailable` error, so the turn fails instead of the model guessing.
Future<ToolResult<O>> _run<O>(
  String name,
  Map<String, dynamic>? context,
  Future<O> Function(XpenseContext c) body,
) async {
  final c = XpenseContext.of(context);
  try {
    return .response(await body(c));
  } on HouseholdUnavailable catch (e) {
    _log.warning('$name: household data unavailable (${e.operation})');
    throw GenkitException('household_unavailable', status: .unavailable);
  }
}
