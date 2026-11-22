// Server half of the catalog parity test (A2UI_CATALOG 1, story S3.2): the
// catalog JSON loads with genkit_a2ui's `loadCatalog`, exactly as the agent
// registers it, and Express written against it compiles to the property
// names the phone reads. The phone half compares the same JSON with
// `Catalog.fromJson` and the Dart implementations (app/test/a2ui).
//
// genkit_a2ui 0.6.0 resolves a2ui_core 0.7.0, the server's version (D-05).
// It is a dev dependency here only.
import 'dart:convert';

import 'package:genkit/genkit.dart';
import 'package:genkit_a2ui/a2ui.dart';
import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'catalog_json.dart';

/// Compiles one Express block in strict mode and returns the messages as
/// plain JSON.
List<Map<String, Object?>> _compile(
  A2uiCatalog catalog,
  String source, {
  List<A2uiEnvelope> history = const [],
}) {
  final parser = A2uiStreamParser(catalog: catalog, history: history);
  final first = parser.push('<a2ui>\n$source\n</a2ui>');
  final last = parser.flush();
  final envelopes = [
    for (final segment in [...first.segments, ...last.segments])
      if (segment is EnvelopeSegment) ...segment.envelopes,
  ];
  return (jsonDecode(jsonEncode(envelopes)) as List<Object?>)
      .cast<Map<String, Object?>>();
}

/// The components of the `createSurface` among [messages], by id.
Map<String, Map<String, Object?>> _components(
  List<Map<String, Object?>> messages,
) {
  final create = messages
      .map((m) => m['createSurface'])
      .whereType<Map<String, Object?>>()
      .single;
  return {
    for (final c
        in (create['components']! as List).cast<Map<String, Object?>>())
      c['id']! as String: c,
  };
}

/// One Express call per Xpense component with every positional argument,
/// and the properties the compiled component must carry. Proves on the
/// server that positional order maps to the names in A2UI_CATALOG 3.
final Map<String, (String, Map<String, Object?>)> _positional = {
  'EntryList': (
    r'root = EntryList($/drafts, "review", "I found two things in that:")',
    {
      'drafts': {'@path': '/drafts'},
      'status': 'review',
      'title': 'I found two things in that:',
    },
  ),
  'ChoicePrompt': (
    'root = ChoicePrompt("Which account?", [{label: "Checking", value: '
        '"acc_chk"}, {label: "Cash", value: "acc_cash", hint: "Wallet"}], '
        r'$/drafts/0/accountId, true, Event("xp.answer", {field: "accountId", '
        r'value: $/drafts/0/accountId}))',
    {
      'question': 'Which account?',
      'value': {'@path': '/drafts/0/accountId'},
      'allowOther': true,
      'action': {
        'event': {
          'name': 'xp.answer',
          'context': {
            'field': 'accountId',
            'value': {'@path': '/drafts/0/accountId'},
          },
        },
      },
    },
  ),
  'Transcript': (
    'root = Transcript("Spent ten thousand dinars on lunch", 6)',
    {'text': 'Spent ten thousand dinars on lunch', 'seconds': 6},
  ),
  'ReceiptSummary': (
    r'root = ReceiptSummary($/receipt, $/drafts, $/ui/split, "cloud")',
    {
      'receipt': {'@path': '/receipt'},
      'drafts': {'@path': '/drafts'},
      'split': {'@path': '/ui/split'},
      'source': 'cloud',
    },
  ),
  'SavedNote': (
    'root = SavedNote("Saved two entries.", "ok")',
    {'text': 'Saved two entries.', 'tone': 'ok'},
  ),
  'MoneyText': (
    r'root = MoneyText($/result/total, "USD", "large", "minus", "muted", '
        '{amountMinor: 8294700, currency: "IQD"})',
    {
      'amountMinor': {'@path': '/result/total'},
      'currency': 'USD',
      'size': 'large',
      'sign': 'minus',
      'tone': 'muted',
      'approx': {'amountMinor': 8294700, 'currency': 'IQD'},
    },
  ),
  'LedgerRow': (
    'root = LedgerRow("Income", 565000, "USD", "income")',
    {
      'label': 'Income',
      'amountMinor': 565000,
      'currency': 'USD',
      'dot': 'income',
    },
  ),
  'MiniBars': (
    r'root = MiniBars($/result/days, "avg 210/day", "max", "Daily spending, '
        'highest on the 14th")',
    {
      'values': {'@path': '/result/days'},
      'caption': 'avg 210/day',
      'highlight': 'max',
      'description': 'Daily spending, highest on the 14th',
    },
  ),
  'BreakdownList': (
    r'root = BreakdownList($/result/rows, "USD", "Total")',
    {
      'items': {'@path': '/result/rows'},
      'currency': 'USD',
      'totalLabel': 'Total',
    },
  ),
  'TransactionList': (
    r'root = TransactionList($/result/txns, "Nothing this week.")',
    {
      'items': {'@path': '/result/txns'},
      'emptyText': 'Nothing this week.',
    },
  ),
  'BudgetMeter': (
    'root = BudgetMeter("Dining", 85000, 120000, "IQD")',
    {
      'label': 'Dining',
      'spentMinor': 85000,
      'limitMinor': 120000,
      'currency': 'IQD',
    },
  ),
  'LoanCard': (
    'root = LoanCard("Alex", "given", 20000, 30000, "USD", "2026-12-15", '
        '"loan_7")',
    {
      'personName': 'Alex',
      'direction': 'given',
      'outstandingMinor': 20000,
      'principalMinor': 30000,
      'currency': 'USD',
      'dueOn': '2026-12-15',
      'loanId': 'loan_7',
    },
  ),
  'GoalCard': (
    'root = GoalCard("Holiday", 120000, 300000, "USD", "On track", "goal_2")',
    {
      'name': 'Holiday',
      'savedMinor': 120000,
      'targetMinor': 300000,
      'currency': 'USD',
      'pace': 'On track',
      'goalId': 'goal_2',
    },
  ),
  'Nudge': (
    'root = Nudge("Internet is usually paid by the 5th.", "bill", "Add", '
        'Event("xp.more", {topic: "internet"}))',
    {
      'text': 'Internet is usually paid by the 5th.',
      'kind': 'bill',
      'actionLabel': 'Add',
      'action': {
        'event': {
          'name': 'xp.more',
          'context': {'topic': 'internet'},
        },
      },
    },
  ),
  'SuggestionChips': (
    'root = SuggestionChips([{label: "By week", message: "Show food by '
        'week"}])',
    {
      'options': [
        {'label': 'By week', 'message': 'Show food by week'},
      ],
    },
  ),
  'Notice': (
    'root = Notice("You are offline. This will send when you are back.", '
        '"offline", "Retry", Event("xp.refine", {note: "retry"}))',
    {
      'text': 'You are offline. This will send when you are back.',
      'kind': 'offline',
      'actionLabel': 'Retry',
      'action': {
        'event': {
          'name': 'xp.refine',
          'context': {'note': 'retry'},
        },
      },
    },
  ),
};

/// The illustrative blocks of A2UI_CATALOG 7, verbatim.
const Map<String, String> _docBlocks = {
  'two_entries': r'''
surface("cap_k3m9")
$/drafts = [
  {id: "d1", intent: "income", amountMinor: 320000, currency: "USD", categoryId: "salary",
   accountId: "acc_chk", who: "me", occurredOn: "2026-11-22", title: "Salary",
   confidence: {intent: 0.99, category: 0.97, account: 0.96}},
  {id: "d2", intent: "expense", amountMinor: 140000, currency: "USD", categoryId: "rent",
   accountId: "acc_chk", who: "joint", occurredOn: "2026-11-22", title: "Rent",
   confidence: {intent: 0.98, category: 0.99, account: 0.97}, guessed: ["who"]}
]
root = EntryList($/drafts, "review", "I found two things in that:")''',
  'intent_question': r'''
surface("cap_p7x2")
$/drafts = [{id: "d1", intent: "loan_given", amountMinor: 30000, currency: "USD",
  personName: "Alex", accountId: "acc_chk", occurredOn: "2026-11-22", missing: ["intent"]}]
root = Column([ask, list])
ask = ChoicePrompt("Quick check, so I file it right: will Alex pay this back?",
  [{label: "Yes, it's a loan", value: "loan_given", hint: "Alex owes us"},
   {label: "No, gift or payment", value: "expense", hint: "Expense"},
   {label: "I was paying Alex back", value: "repayment_made", hint: "Debt"}],
  $/drafts/0/intent)
list = EntryList($/drafts)''',
  'analytics_answer': r'''
surface("ans_food_nov")
$/result = {total: 48650, rows: [{label: "Groceries", amountMinor: 38600, share: 0.79},
  {label: "Dining", amountMinor: 10050, share: 0.21}]}
root = Column([head, total, rows, chips])
head = Text("Food in November")
total = MoneyText($/result/total, "USD", "large")
rows = BreakdownList($/result/rows, "USD")
chips = SuggestionChips([{label: "By week", message: "Show food spending by week this month"},
  {label: "Compare to October", message: "Compare food spending with October"}])''',
};

void main() {
  late Genkit ai;
  late A2uiCatalog catalog;

  setUpAll(() async {
    ai = Genkit(isDevEnv: false);
    catalog = await loadCatalog(
      ai,
      id: xpenseCatalogLookupId,
      file: xpenseCatalogPackagePath,
    );
  });

  tearDownAll(() => ai.shutdown());

  test('loadCatalog registers the file under "xpense" with its own id', () {
    expect(catalog.id, xpenseCatalogId);
    expect(catalog.protocolVersion, xpenseProtocolVersion);
    expect(resolveCatalog(ai.registry, xpenseCatalogLookupId).id, catalog.id);
  });

  test('loadCatalog sees the same components and properties, in order', () {
    final json = componentsOf(readCatalogJson());
    expect(catalog.components.keys, orderedEquals(xpenseComponentNames));
    for (final name in xpenseComponentNames) {
      final loaded = catalog.components[name]!.schema;
      expect(
        propsOf(loaded).map((p) => p.name),
        orderedEquals(propsOf(json[name]!).map((p) => p.name)),
        reason: name,
      );
    }
    expect(catalog.functions.keys, orderedEquals(xpenseFunctionNames));
  });

  group('Express compiles in strict mode to the documented names', () {
    for (final MapEntry(key: name, value: (source, expected))
        in _positional.entries) {
      test(name, () {
        final messages = _compile(
          catalog,
          'surface("pos_${name.toLowerCase()}")\n$source',
        );
        final root = _components(messages)['root']!;
        expect(root['component'], name);
        expected.forEach((key, value) {
          expect(root[key], value, reason: '$name.$key');
        });
      });
    }

    test('Button checks come after action now that weight is gone', () {
      final messages = _compile(catalog, r'''
surface("pos_button")
$/answer/note = ""
root = Button(label, "primary", Event("xp.answer", {field: "note", text: $/answer/note}), [?required($/answer/note, "Say a few words")])
label = Text("Send")''');
      final root = _components(messages)['root']!;
      expect(root['child'], 'label');
      expect(root['variant'], 'primary');
      expect(
        (root['checks']! as List).single,
        containsPair('message', 'Say a few words'),
      );
    });

    for (final MapEntry(key: name, value: source) in _docBlocks.entries) {
      test('A2UI_CATALOG 7: $name', () {
        final messages = _compile(catalog, source);
        final create = messages.last['createSurface']! as Map<String, Object?>;
        expect(create['catalogId'], xpenseCatalogId);
        expect(create['dataModel'], isA<Map<String, Object?>>());
      });
    }
  });

  test('an enum property cannot be bound (static in Express)', () {
    expect(
      () => _compile(catalog, r'''
surface("pos_static")
$/status = "saved"
root = EntryList($/drafts, $/status)'''),
      throwsA(
        predicate((e) => '$e'.contains('not one of the allowed enum values')),
      ),
    );
  });

  test('injected instructions stay within the measured budget', () {
    // WP-S1 Q7 measured 22,003 characters for the sizing draft with
    // `weight` and long descriptions; this catalog renders about 18,300
    // (≈ 4,600 to 5,200 tokens), and must not grow past the draft.
    final text = renderCatalogInstructions(catalog);
    printOnFailure('instructions: ${text.length} characters');
    expect(text.length, lessThan(22003));
  });
}
