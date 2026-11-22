// The catalog JSON against the contract in A2UI_CATALOG 3 and 4 (story
// S3.2). Express is positional, so the order of every component's
// properties is part of the contract: reordering one is a breaking change
// (A2UI_CATALOG 10) and must fail here.
import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'catalog_json.dart';

const String _columnJustify =
    'start|center|end|spaceBetween|spaceAround|spaceEvenly|stretch';
const String _rowJustify =
    'center|end|spaceAround|spaceBetween|spaceEvenly|start|stretch';

/// A2UI_CATALOG 3, one line per property in positional order: name, `?` when
/// optional, then the kind (common type, `enum(…)` for a static enum, or the
/// JSON type of another static property).
const Map<String, List<String>> _contract = {
  // 3.1 Basic subset (same names and schemas as the v1.0 basic catalog).
  'Column': [
    'children ChildList',
    'justify? enum($_columnJustify)',
    'align? enum(center|end|start|stretch)',
  ],
  'Row': [
    'children ChildList',
    'justify? enum($_rowJustify)',
    'align? enum(start|center|end|stretch)',
  ],
  'List': [
    'children ChildList',
    'direction? enum(vertical|horizontal)',
    'align? enum(start|center|end|stretch)',
  ],
  'Text': ['text DynamicString', 'variant? enum(caption|body)'],
  'Divider': ['axis? enum(horizontal|vertical)'],
  'Button': [
    'child Child',
    'variant? enum(default|primary|borderless)',
    'action Action',
  ],
  'TextField': [
    'label DynamicString',
    'value DynamicString',
    'placeholder? DynamicString',
    'variant? enum(longText|number|shortText)',
  ],
  'DateTimeInput': [
    'value DynamicString',
    'enableDate? boolean',
    'enableTime? boolean',
    'min? DynamicString',
    'max? DynamicString',
    'label? DynamicString',
  ],
  // 3.2 Capture.
  'EntryList': [
    'drafts DynamicValue',
    'status? enum(review|saved)',
    'title? DynamicString',
  ],
  'ChoicePrompt': [
    'question DynamicString',
    'options array',
    'value DynamicString',
    'allowOther? boolean',
    'action? Action',
  ],
  'Transcript': ['text DynamicString', 'seconds? DynamicNumber'],
  'ReceiptSummary': [
    'receipt DynamicValue',
    'drafts DynamicValue',
    'split DynamicBoolean',
    'source? enum(device|cloud)',
  ],
  'SavedNote': ['text DynamicString', 'tone? enum(ok|info|warn)'],
  // 3.3 Figures and review.
  'MoneyText': [
    'amountMinor DynamicNumber',
    'currency DynamicString',
    'size? enum(hero|large|body|small)',
    'sign? enum(none|plus|minus)',
    'tone? enum(ink|income|muted|loan|saving)',
    'approx? DynamicValue',
  ],
  'LedgerRow': [
    'label DynamicString',
    'amountMinor DynamicNumber',
    'currency DynamicString',
    'dot? enum(income|spent|saved|loan|neutral)',
  ],
  'MiniBars': [
    'values DynamicValue',
    'caption? DynamicString',
    'highlight? enum(last|max|none)',
    'description DynamicString',
  ],
  'BreakdownList': [
    'items DynamicValue',
    'currency DynamicString',
    'totalLabel? DynamicString',
  ],
  'TransactionList': ['items DynamicValue', 'emptyText? DynamicString'],
  'BudgetMeter': [
    'label DynamicString',
    'spentMinor DynamicNumber',
    'limitMinor DynamicNumber',
    'currency DynamicString',
  ],
  'LoanCard': [
    'personName DynamicString',
    'direction enum(given|taken)',
    'outstandingMinor DynamicNumber',
    'principalMinor DynamicNumber',
    'currency DynamicString',
    'dueOn? DynamicString',
    'loanId? DynamicString',
  ],
  'GoalCard': [
    'name DynamicString',
    'savedMinor DynamicNumber',
    'targetMinor DynamicNumber',
    'currency DynamicString',
    'pace? DynamicString',
    'goalId? DynamicString',
  ],
  // 3.4 Conversation.
  'Nudge': [
    'text DynamicString',
    'kind enum(bill|budget|loan|rate|report|info)',
    'actionLabel? DynamicString',
    'action? Action',
  ],
  'SuggestionChips': ['options array'],
  'Notice': [
    'text DynamicString',
    'kind enum(offline|limit|privacy|error)',
    'actionLabel? DynamicString',
    'action? Action',
  ],
};

/// Components that take `checks` (the basic inputs and the Button).
const Set<String> _checkable = {'Button', 'TextField', 'DateTimeInput'};

/// Envelope keys the renderer reads itself (A2UI_CATALOG 2 rule 7).
const Set<String> _reserved = {
  'checks',
  'metadata',
  'accessibility',
  'catalogId',
};

String _line(CatalogProp p) => '${p.name}${p.required ? '' : '?'} ${p.kind}';

void main() {
  final catalog = readCatalogJson();
  final components = componentsOf(catalog);

  group('identity (A2UI_CATALOG 1)', () {
    test(r'catalogId, $id and protocolVersion', () {
      expect(catalog['catalogId'], xpenseCatalogId);
      expect(catalog[r'$id'], xpenseCatalogId);
      expect(catalog['protocolVersion'], xpenseProtocolVersion);
    });

    test('the 24 components, in catalog order', () {
      expect(components.keys, orderedEquals(xpenseComponentNames));
      expect(components.keys, orderedEquals(_contract.keys));
      expect(components, hasLength(24));
    });

    test(r'$defs.anyComponent lists every component and nothing else', () {
      // a2ui_core's Catalog.fromJson keeps only the components the union
      // names, so a missing entry would silently drop a component.
      final defs = catalog[r'$defs']! as Map<String, Object?>;
      final union = (defs['anyComponent']! as Map)['oneOf']! as List<Object?>;
      expect([
        for (final r in union) '${(r! as Map)[r'$ref']}'.split('/').last,
      ], orderedEquals(xpenseComponentNames));
      final functions =
          (defs['anyFunction']! as Map)['oneOf']! as List<Object?>;
      expect([
        for (final r in functions) '${(r! as Map)[r'$ref']}'.split('/').last,
      ], orderedEquals(xpenseFunctionNames));
    });
  });

  group('components (A2UI_CATALOG 3)', () {
    for (final MapEntry(key: name, value: expected) in _contract.entries) {
      test('$name: properties, order, kinds and required', () {
        final schema = components[name]!;
        expect(schema['properties'] ?? schema['allOf'], isNotNull);
        expect(propsOf(schema).map(_line), orderedEquals(expected));
        expect(isCheckable(schema), _checkable.contains(name));
      });
    }

    test('no property uses a reserved envelope name or `weight`', () {
      for (final MapEntry(key: name, value: schema) in components.entries) {
        for (final prop in propsOf(schema)) {
          expect(_reserved, isNot(contains(prop.name)), reason: name);
          expect(prop.name, isNot('weight'), reason: name);
        }
      }
    });

    test('every property has an identifier name (no hyphens)', () {
      final identifier = RegExp(r'^[a-z][A-Za-z0-9]*$');
      for (final MapEntry(key: name, value: schema) in components.entries) {
        expect(name, matches(RegExp(r'^[A-Z][A-Za-z]*$')));
        for (final prop in propsOf(schema)) {
          expect(prop.name, matches(identifier), reason: name);
        }
      }
    });

    test('descriptions are one line', () {
      void walk(Object? node, String where) {
        if (node is Map) {
          final description = node['description'];
          if (description is String) {
            expect(description, isNot(contains('\n')), reason: where);
          }
          for (final MapEntry(:key, :value) in node.entries) {
            walk(value, '$where/$key');
          }
        } else if (node is List) {
          for (final (i, item) in node.indexed) {
            walk(item, '$where/$i');
          }
        }
      }

      walk(catalog, '');
    });

    test('ChoicePrompt takes 2 to 5 options and SuggestionChips at most 4', () {
      Map<String, Object?> options(String component) =>
          (components[component]!['properties']! as Map)['options']!
              as Map<String, Object?>;
      expect(options('ChoicePrompt'), containsPair('minItems', 2));
      expect(options('ChoicePrompt'), containsPair('maxItems', 5));
      expect(options('SuggestionChips'), containsPair('maxItems', 4));
      expect(
        ((options('ChoicePrompt')['items']! as Map)['properties']! as Map).keys,
        orderedEquals(['label', 'value', 'hint']),
      );
      expect(
        ((options('SuggestionChips')['items']! as Map)['properties']! as Map)
            .keys,
        orderedEquals(['label', 'message']),
      );
    });
  });

  group('functions (A2UI_CATALOG 4)', () {
    final functions = catalog['functions']! as Map<String, Object?>;

    test('kept from the basic catalog, nothing else', () {
      expect(functions.keys, orderedEquals(xpenseFunctionNames));
      for (final removed in ['openUrl', 'formatCurrency', 'formatString']) {
        expect(functions.keys, isNot(contains(removed)));
      }
    });

    test('each function names itself under @call', () {
      for (final MapEntry(key: name, value: fn) in functions.entries) {
        final call = ((fn! as Map)['properties']! as Map)['@call']! as Map;
        expect(call['const'], name);
      }
    });
  });

  group('no remote content (A2UI_CATALOG 2 rule 4)', () {
    test('no image, video, audio, modal or link components', () {
      for (final banned in [
        'Image',
        'Icon',
        'Video',
        'AudioPlayer',
        'Card',
        'Tabs',
        'Modal',
        'CheckBox',
        'ChoicePicker',
        'Slider',
      ]) {
        expect(components.keys, isNot(contains(banned)));
      }
    });
  });
}
