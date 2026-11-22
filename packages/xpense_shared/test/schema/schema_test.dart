import 'dart:convert';

import 'package:schemantic/schemantic.dart';
import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Encodes to a JSON string and back, as the wire and Firestore would.
Map<String, dynamic> _wire(Object? json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

final _fullDraft = EntryDraft(
  id: 'd1',
  intent: 'expense',
  amountMinor: 10000,
  currency: 'IQD',
  accountId: 'acc_cash',
  categoryId: 'dining',
  who: 'joint',
  occurredOn: '2026-11-22',
  occurredTime: '13:05',
  title: 'Lunch with the kids',
  note: 'Kebab place',
  fx: FxQuote(
    pair: 'USD/IQD',
    pairRate: '1705',
    source: 'market',
    asOf: '2026-11-22',
    baseAmountMinor: 587,
  ),
  confidence: DraftConfidence(
    intent: 0.97,
    category: 0.8,
    account: 0.6,
    who: 1,
  ),
  guessed: ['category'],
  missing: [],
  duplicate: DuplicateHint(txnId: 't9', probability: 0.12),
  recurring: RecurringHint(
    probability: 0.1,
    unit: 'month',
    interval: 1,
    dayOfMonth: 22,
  ),
  origin: 'parser',
);

final _parseResult = ParseResult(
  amounts: [
    ParsedAmount(
      amountMinor: 25000,
      currency: 'IQD',
      value: '25',
      span: '25',
      start: 0,
      end: 2,
      guessed: true,
    ),
  ],
  currency: 'IQD',
  date: '2026-11-22',
  hints: [
    ParseHint(kind: 'account', span: 'cash', id: 'acc_cash', confidence: 0.9),
    ParseHint(kind: 'who', span: 'we', who: 'joint'),
  ],
  ruleHits: [
    RuleHit(
      ruleId: 'r1',
      field: 'categoryId',
      value: 'dining',
      confidence: 0.99,
    ),
  ],
  signals: ComplexitySignals(
    amountCount: 1,
    hasConjunction: false,
    isQuestion: false,
    isCommand: false,
    hasPersonTransfer: false,
    unresolved: ['account'],
    attachment: 'none',
  ),
);

final _decideRequest = DecideRequest(
  text: 'Spent ten thousand dinars on lunch with the kids',
  lang: 'en',
  parsed: DecideParsed(amountMinor: 10000, currency: 'IQD', date: '2026-11-22'),
  hints: [ParseHint(kind: 'person', span: 'kids')],
  ask: ['intent', 'category', 'account', 'duplicate'],
  candidates: [
    DuplicateCandidate(
      txnId: 't9',
      amountMinor: 10000,
      currency: 'IQD',
      occurredOn: '2026-11-21',
      title: 'Lunch',
    ),
  ],
);

final _decideResponse = DecideResponse(
  intent: ChoiceAnswer(
    choice: 'expense',
    probabilities: {'expense': 0.96, 'other': 0.04},
    confidence: 0.96,
  ),
  category: ChoiceAnswer(choice: 'dining', probabilities: {'dining': 1}),
  multiEntry: YesNoAnswer(probability: 0.02, confidence: 0.98),
  needsFollowup: YesNoAnswer(probability: 0.1),
  isRecurring: YesNoAnswer(probability: 0.05),
  duplicate: YesNoAnswer(probability: 0.3),
  calibrated: true,
);

final _receipt = ReceiptExtraction(
  merchant: 'Carrefour',
  date: '2026-11-20',
  currency: 'IQD',
  totalMinor: 37500,
  lines: [
    ReceiptLine(text: 'Rice 5kg', amountMinor: 12500, categoryId: 'groceries'),
    ReceiptLine(text: 'Tea', amountMinor: 25000),
  ],
);

/// One row per schema: its descriptor, a full instance and a decoder.
final _roundTrips =
    <
      ({
        String name,
        SchemanticType<Object> schema,
        Object instance,
        Map<String, dynamic> Function(Map<String, dynamic>) reparse,
      })
    >[
      (
        name: 'EntryDraft',
        schema: EntryDraft.$schema,
        instance: _fullDraft,
        reparse: (j) => EntryDraft.fromJson(j).toJson(),
      ),
      (
        name: 'FxQuote',
        schema: FxQuote.$schema,
        instance: _fullDraft.fx!,
        reparse: (j) => FxQuote.fromJson(j).toJson(),
      ),
      (
        name: 'DraftConfidence',
        schema: DraftConfidence.$schema,
        instance: _fullDraft.confidence!,
        reparse: (j) => DraftConfidence.fromJson(j).toJson(),
      ),
      (
        name: 'DuplicateHint',
        schema: DuplicateHint.$schema,
        instance: _fullDraft.duplicate!,
        reparse: (j) => DuplicateHint.fromJson(j).toJson(),
      ),
      (
        name: 'RecurringHint',
        schema: RecurringHint.$schema,
        instance: _fullDraft.recurring!,
        reparse: (j) => RecurringHint.fromJson(j).toJson(),
      ),
      (
        name: 'ParseResult',
        schema: ParseResult.$schema,
        instance: _parseResult,
        reparse: (j) => ParseResult.fromJson(j).toJson(),
      ),
      (
        name: 'DecideRequest',
        schema: DecideRequest.$schema,
        instance: _decideRequest,
        reparse: (j) => DecideRequest.fromJson(j).toJson(),
      ),
      (
        name: 'DecideResponse',
        schema: DecideResponse.$schema,
        instance: _decideResponse,
        reparse: (j) => DecideResponse.fromJson(j).toJson(),
      ),
      (
        name: 'ReceiptExtraction',
        schema: ReceiptExtraction.$schema,
        instance: _receipt,
        reparse: (j) => ReceiptExtraction.fromJson(j).toJson(),
      ),
    ];

Map<String, dynamic> _toJson(Object instance) =>
    (instance as dynamic).toJson() as Map<String, dynamic>;

void main() {
  group('round trip through JSON text', () {
    for (final row in _roundTrips) {
      test(row.name, () {
        final json = _toJson(row.instance);
        final wire = _wire(json);
        expect(row.reparse(wire), _wire(json));
        expect(_wire(row.schema.serialize(row.schema.parse(wire))), wire);
      });
    }
  });

  group('full instances validate against their JSON Schema', () {
    for (final row in _roundTrips) {
      test(row.name, () async {
        final errors = await row.schema.validate(_wire(_toJson(row.instance)));
        expect(errors.map((e) => e.toErrorString()), isEmpty);
      });
    }
  });

  group('EntryDraft', () {
    test('typed getters read back what was written', () {
      final draft = EntryDraft.fromJson(_wire(_fullDraft.toJson()));
      expect(draft.amountMinor, 10000);
      expect(draft.fx?.pairRate, '1705');
      expect(draft.fx?.baseAmountMinor, 587);
      expect(draft.confidence?.who, 1.0);
      expect(draft.guessed, ['category']);
      expect(draft.recurring?.dayOfMonth, 22);
    });

    test('a partial draft (id and intent only) parses and validates', () async {
      final json = {'id': 'd2', 'intent': 'loan_given'};
      final draft = EntryDraft.fromJson(json);
      expect(draft.amountMinor, isNull);
      expect(draft.currency, isNull);
      expect(draft.fx, isNull);
      expect(draft.confidence, isNull);
      expect(draft.guessed, isNull);
      expect(draft.origin, isNull);
      expect(await EntryDraft.$schema.validate(json), isEmpty);
    });

    test('explicit nulls from a model or reloaded state still read', () {
      final draft = EntryDraft.fromJson({
        'id': 'd3',
        'intent': 'expense',
        'amountMinor': null,
        'fx': null,
        'guessed': null,
      });
      expect(draft.amountMinor, isNull);
      expect(draft.fx, isNull);
      expect(draft.guessed, isNull);
    });

    test('an integer amount encoded as 12.0 reads as int', () {
      final draft = EntryDraft.fromJson({
        'id': 'd4',
        'intent': 'expense',
        'amountMinor': 1250.0,
      });
      expect(draft.amountMinor, 1250);
    });

    final invalid =
        <({String name, Map<String, Object?> json, ValidationErrorType type})>[
          (
            name: 'non-money intent',
            json: {'id': 'x', 'intent': 'question'},
            type: ValidationErrorType.enumValueNotAllowed,
          ),
          (
            name: 'unknown currency',
            json: {'id': 'x', 'intent': 'expense', 'currency': 'EUR'},
            type: ValidationErrorType.enumValueNotAllowed,
          ),
          (
            name: 'zero amount',
            json: {'id': 'x', 'intent': 'expense', 'amountMinor': 0},
            type: ValidationErrorType.minimumNotMet,
          ),
          (
            name: 'fractional amount',
            json: {'id': 'x', 'intent': 'expense', 'amountMinor': 12.5},
            type: ValidationErrorType.typeMismatch,
          ),
          (
            name: 'unknown who',
            json: {'id': 'x', 'intent': 'expense', 'who': 'kids'},
            type: ValidationErrorType.enumValueNotAllowed,
          ),
          (
            name: 'confidence above 1',
            json: {
              'id': 'x',
              'intent': 'expense',
              'confidence': {'intent': 1.2},
            },
            type: ValidationErrorType.maximumExceeded,
          ),
          (
            name: 'fx without a rate',
            json: {
              'id': 'x',
              'intent': 'expense',
              'fx': {'pair': 'USD/IQD'},
            },
            type: ValidationErrorType.requiredPropertyMissing,
          ),
          (
            name: 'missing intent',
            json: {'id': 'x'},
            type: ValidationErrorType.requiredPropertyMissing,
          ),
        ];
    for (final c in invalid) {
      test('rejects ${c.name}', () async {
        final errors = await EntryDraft.$schema.validate(c.json);
        expect(errors.map((e) => e.error), contains(c.type));
      });
    }
  });

  group('JSON Schema enums come from the shared constants', () {
    Map<String, dynamic> props(SchemanticType<Object> schema) =>
        schema.jsonSchema()['properties']! as Map<String, dynamic>;

    List<Object?>? enumOf(Map<String, dynamic> properties, String field) =>
        (properties[field] as Map<String, dynamic>)['enum'] as List<Object?>?;

    test('EntryDraft', () {
      final p = props(EntryDraft.$schema);
      expect(enumOf(p, 'intent'), entryIntentWireValues);
      expect(enumOf(p, 'currency'), supportedCurrencyCodes);
      expect(enumOf(p, 'who'), whoValues);
      expect(enumOf(p, 'origin'), draftOriginValues);
      // Nested schemas are inlined for model structured output.
      final fx = p['fx'] as Map<String, dynamic>;
      final fxProps = fx['properties'] as Map<String, dynamic>;
      expect(enumOf(fxProps, 'source'), fxSourceValues);
      expect(fx['required'], ['pair', 'pairRate']);
    });

    test('only id and intent are required on EntryDraft', () {
      expect(EntryDraft.$schema.jsonSchema()['required'], ['id', 'intent']);
    });

    test('DecideResponse keys match the Decisions question keys', () {
      final keys = props(DecideResponse.$schema).keys.toSet();
      expect(keys, containsAll(decideQuestionKeys));
      expect(keys.difference(decideQuestionKeys.toSet()), {
        'calibrated',
        'unavailable',
      });
    });

    test('ComplexitySignals attachment and ParseHint kinds', () {
      final signals =
          props(ParseResult.$schema)['signals'] as Map<String, dynamic>;
      final signalProps = signals['properties'] as Map<String, dynamic>;
      expect(enumOf(signalProps, 'attachment'), attachmentValues);
    });
  });

  group('DecideResponse', () {
    test('snake_case keys on the wire, camelCase in Dart', () {
      final json = _wire(_decideResponse.toJson());
      expect(json.keys, containsAll(['multi_entry', 'needs_followup']));
      expect(json.keys, contains('is_recurring'));
      final parsed = DecideResponse.fromJson(json);
      expect(parsed.multiEntry?.probability, 0.02);
      expect(parsed.needsFollowup?.probability, 0.1);
    });

    test('integer probabilities (0 or 1) still read', () {
      final parsed = DecideResponse.fromJson(
        _wire({
          'category': {
            'choice': 'dining',
            'probabilities': {'dining': 1, 'groceries': 0},
          },
        }),
      );
      expect(parsed.category?.probabilities, {'dining': 1, 'groceries': 0});
    });

    test('the unavailable fallback is a valid response', () async {
      final json = {'unavailable': true};
      expect(DecideResponse.fromJson(json).unavailable, isTrue);
      expect(await DecideResponse.$schema.validate(json), isEmpty);
    });
  });

  group('ReceiptExtraction', () {
    test('line amounts can be split with allocate', () {
      final receipt = ReceiptExtraction.fromJson(_wire(_receipt.toJson()));
      final lines = receipt.lines!;
      expect(lines.map((l) => l.amountMinor), [12500, 25000]);
      expect(lines.last.categoryId, isNull);
      final shares = allocate(1000, [for (final l in lines) l.amountMinor]);
      expect(shares, [333, 667]);
    });

    test('a receipt line needs text and an amount', () async {
      final errors = await ReceiptExtraction.$schema.validate({
        'lines': [
          {'text': 'Tea'},
        ],
      });
      expect(
        errors.map((e) => e.error),
        contains(ValidationErrorType.requiredPropertyMissing),
      );
    });
  });
}
