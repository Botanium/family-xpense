/// The phone's Xpense catalog (A2UI_CATALOG 1 and 9): one
/// `ComponentImplementation` per component of `xpense_catalog.json`, in
/// catalog order, and the functions kept from the basic catalog. The parity
/// test checks both against the JSON.
library;

import 'package:a2ui_core/a2ui_core.dart';
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:xpense_app/a2ui/components/breakdown_list.dart';
import 'package:xpense_app/a2ui/components/budget_meter.dart';
import 'package:xpense_app/a2ui/components/button.dart';
import 'package:xpense_app/a2ui/components/choice_prompt.dart';
import 'package:xpense_app/a2ui/components/column.dart';
import 'package:xpense_app/a2ui/components/date_time_input.dart';
import 'package:xpense_app/a2ui/components/divider.dart';
import 'package:xpense_app/a2ui/components/entry_list.dart';
import 'package:xpense_app/a2ui/components/goal_card.dart';
import 'package:xpense_app/a2ui/components/ledger_row.dart';
import 'package:xpense_app/a2ui/components/list.dart';
import 'package:xpense_app/a2ui/components/loan_card.dart';
import 'package:xpense_app/a2ui/components/mini_bars.dart';
import 'package:xpense_app/a2ui/components/money_text.dart';
import 'package:xpense_app/a2ui/components/notice.dart';
import 'package:xpense_app/a2ui/components/nudge.dart';
import 'package:xpense_app/a2ui/components/receipt_summary.dart';
import 'package:xpense_app/a2ui/components/row.dart';
import 'package:xpense_app/a2ui/components/saved_note.dart';
import 'package:xpense_app/a2ui/components/suggestion_chips.dart';
import 'package:xpense_app/a2ui/components/text.dart';
import 'package:xpense_app/a2ui/components/text_field.dart';
import 'package:xpense_app/a2ui/components/transaction_list.dart';
import 'package:xpense_app/a2ui/components/transcript.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Every component, in catalog order.
final List<ComponentImplementation> xpenseComponents = [
  columnComponent,
  rowComponent,
  listComponent,
  textComponent,
  dividerComponent,
  buttonComponent,
  textFieldComponent,
  dateTimeInputComponent,
  entryListComponent,
  choicePromptComponent,
  transcriptComponent,
  receiptSummaryComponent,
  savedNoteComponent,
  moneyTextComponent,
  ledgerRowComponent,
  miniBarsComponent,
  breakdownListComponent,
  transactionListComponent,
  budgetMeterComponent,
  loanCardComponent,
  goalCardComponent,
  nudgeComponent,
  suggestionChipsComponent,
  noticeComponent,
];

/// The basic-catalog functions the Xpense catalog keeps (A2UI_CATALOG 4).
List<FunctionImplementation> xpenseFunctions({String locale = 'en-US'}) {
  final basic = BasicCatalog.v1_0(locale: locale).functions;
  return [for (final name in xpenseFunctionNames) basic[name]!];
}

/// The catalog the surface host registers.
CatalogImplementation xpenseCatalog({String locale = 'en-US'}) =>
    CatalogImplementation(
      id: xpenseCatalogId,
      protocolVersion: A2uiProtocolVersion.v1_0,
      components: xpenseComponents,
      functions: xpenseFunctions(locale: locale),
    );
