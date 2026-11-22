// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parse_result.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

/// Output of the on-device fast parser (AI_PIPELINE 5, step 8):
/// `{amounts[], currency?, date, hints, ruleHits, signals}`.
///
/// The parser itself is WP-30 (`lib/parse/`); this is its contract.
base class ParseResult {
  /// Creates a [ParseResult] from a JSON map.
  factory ParseResult.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  ParseResult._(this._json);

  ParseResult({
    List<ParsedAmount>? amounts,
    String? currency,
    String? date,
    List<ParseHint>? hints,
    List<RuleHit>? ruleHits,
    ComplexitySignals? signals,
  }) {
    _json = {
      'amounts': ?amounts?.map((e) => e.toJson()).toList(),
      'currency': ?currency,
      'date': ?date,
      'hints': ?hints?.map((e) => e.toJson()).toList(),
      'ruleHits': ?ruleHits?.map((e) => e.toJson()).toList(),
      'signals': ?signals?.toJson(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [ParseResult].
  static const SchemanticType<ParseResult> $schema = _ParseResultTypeFactory();

  /// Every amount found, in message order.
  List<ParsedAmount>? get amounts {
    return (_json['amounts'] as List?)
        ?.map((e) => ParsedAmount.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Every amount found, in message order.
  set amounts(List<ParsedAmount>? value) {
    if (value == null) {
      _json.remove('amounts');
    } else {
      _json['amounts'] = value.map((e) => e.toJson()).toList();
    }
  }

  /// The message-level currency, when one was settled.
  String? get currency {
    return _json['currency'] as String?;
  }

  /// The message-level currency, when one was settled.
  set currency(String? value) {
    if (value == null) {
      _json.remove('currency');
    } else {
      _json['currency'] = value;
    }
  }

  /// The resolved household-local date, `YYYY-MM-DD` (default: today).
  String? get date {
    return _json['date'] as String?;
  }

  /// The resolved household-local date, `YYYY-MM-DD` (default: today).
  set date(String? value) {
    if (value == null) {
      _json.remove('date');
    } else {
      _json['date'] = value;
    }
  }

  /// Account, person, category and who hints matched in the text.
  List<ParseHint>? get hints {
    return (_json['hints'] as List?)
        ?.map((e) => ParseHint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Account, person, category and who hints matched in the text.
  set hints(List<ParseHint>? value) {
    if (value == null) {
      _json.remove('hints');
    } else {
      _json['hints'] = value.map((e) => e.toJson()).toList();
    }
  }

  /// Learned rules that matched.
  List<RuleHit>? get ruleHits {
    return (_json['ruleHits'] as List?)
        ?.map((e) => RuleHit.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Learned rules that matched.
  set ruleHits(List<RuleHit>? value) {
    if (value == null) {
      _json.remove('ruleHits');
    } else {
      _json['ruleHits'] = value.map((e) => e.toJson()).toList();
    }
  }

  /// Complexity signals for the router (AI_PIPELINE 2).
  ComplexitySignals? get signals {
    return _json['signals'] == null
        ? null
        : ComplexitySignals.fromJson(_json['signals'] as Map<String, dynamic>);
  }

  /// Complexity signals for the router (AI_PIPELINE 2).
  set signals(ComplexitySignals? value) {
    if (value == null) {
      _json.remove('signals');
    } else {
      _json['signals'] = value.toJson();
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [ParseResult] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _ParseResultTypeFactory extends SchemanticType<ParseResult> {
  const _ParseResultTypeFactory();

  @override
  ParseResult parse(Object? json) {
    return ParseResult._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'ParseResult',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Output of the deterministic fast parser.',
      'properties': <String, Object?>{
        'amounts': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/ParsedAmount'},
        },
        'currency': <String, Object?>{
          'type': 'string',
          'enum': ['USD', 'IQD'],
        },
        'date': <String, Object?>{
          'type': 'string',
          'description': 'Resolved household-local date, YYYY-MM-DD.',
        },
        'hints': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/ParseHint'},
        },
        'ruleHits': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/RuleHit'},
        },
        'signals': <String, Object?>{r'$ref': r'#/$defs/ComplexitySignals'},
      },
    },
    dependencies: [
      ParsedAmount.$schema,
      ParseHint.$schema,
      RuleHit.$schema,
      ComplexitySignals.$schema,
    ],
  );
}

/// One amount found by the parser.
base class ParsedAmount {
  /// Creates a [ParsedAmount] from a JSON map.
  factory ParsedAmount.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  ParsedAmount._(this._json);

  ParsedAmount({
    int? amountMinor,
    String? currency,
    String? value,
    String? span,
    int? start,
    int? end,
    bool? guessed,
  }) {
    _json = {
      'amountMinor': ?amountMinor,
      'currency': ?currency,
      'value': ?value,
      'span': ?span,
      'start': ?start,
      'end': ?end,
      'guessed': ?guessed,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [ParsedAmount].
  static const SchemanticType<ParsedAmount> $schema =
      _ParsedAmountTypeFactory();

  /// Amount in minor units of [currency]; set when the currency is known.
  int? get amountMinor {
    return (_json['amountMinor'] as num?)?.toInt();
  }

  /// Amount in minor units of [currency]; set when the currency is known.
  set amountMinor(int? value) {
    if (value == null) {
      _json.remove('amountMinor');
    } else {
      _json['amountMinor'] = value;
    }
  }

  /// The amount's currency, from a currency word or the account default.
  String? get currency {
    return _json['currency'] as String?;
  }

  /// The amount's currency, from a currency word or the account default.
  set currency(String? value) {
    if (value == null) {
      _json.remove('currency');
    } else {
      _json['currency'] = value;
    }
  }

  /// The exact major-unit value as a plain decimal string, for example
  /// `"25000"` or `"12.5"`, kept when the currency is not yet known.
  String? get value {
    return _json['value'] as String?;
  }

  /// The exact major-unit value as a plain decimal string, for example
  /// `"25000"` or `"12.5"`, kept when the currency is not yet known.
  set value(String? value) {
    if (value == null) {
      _json.remove('value');
    } else {
      _json['value'] = value;
    }
  }

  /// The matched text span.
  String? get span {
    return _json['span'] as String?;
  }

  /// The matched text span.
  set span(String? value) {
    if (value == null) {
      _json.remove('span');
    } else {
      _json['span'] = value;
    }
  }

  /// Start offset of [span] in the normalised text.
  int? get start {
    return (_json['start'] as num?)?.toInt();
  }

  /// Start offset of [span] in the normalised text.
  set start(int? value) {
    if (value == null) {
      _json.remove('start');
    } else {
      _json['start'] = value;
    }
  }

  /// End offset (exclusive) of [span] in the normalised text.
  int? get end {
    return (_json['end'] as num?)?.toInt();
  }

  /// End offset (exclusive) of [span] in the normalised text.
  set end(int? value) {
    if (value == null) {
      _json.remove('end');
    } else {
      _json['end'] = value;
    }
  }

  /// Whether the amount was inferred (for example dropped thousands) and
  /// should show the "Guessed" badge.
  bool? get guessed {
    return _json['guessed'] as bool?;
  }

  /// Whether the amount was inferred (for example dropped thousands) and
  /// should show the "Guessed" badge.
  set guessed(bool? value) {
    if (value == null) {
      _json.remove('guessed');
    } else {
      _json['guessed'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [ParsedAmount] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _ParsedAmountTypeFactory extends SchemanticType<ParsedAmount> {
  const _ParsedAmountTypeFactory();

  @override
  ParsedAmount parse(Object? json) {
    return ParsedAmount._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'ParsedAmount',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'An amount found in the message.',
      'properties': <String, Object?>{
        'amountMinor': <String, Object?>{
          'type': 'integer',
          'description': 'Amount in minor units of currency.',
          'minimum': 0,
        },
        'currency': <String, Object?>{
          'type': 'string',
          'enum': ['USD', 'IQD'],
        },
        'value': <String, Object?>{
          'type': 'string',
          'description': 'Major-unit value as a plain decimal string.',
        },
        'span': <String, Object?>{'type': 'string'},
        'start': <String, Object?>{'type': 'integer', 'minimum': 0},
        'end': <String, Object?>{'type': 'integer', 'minimum': 0},
        'guessed': <String, Object?>{'type': 'boolean'},
      },
    },
    dependencies: [],
  );
}

/// A hint matched against the household's names and aliases.
base class ParseHint {
  /// Creates a [ParseHint] from a JSON map.
  factory ParseHint.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  ParseHint._(this._json);

  ParseHint({
    required String kind,
    String? span,
    String? id,
    String? who,
    double? confidence,
  }) {
    _json = {
      'kind': kind,
      'span': ?span,
      'id': ?id,
      'who': ?who,
      'confidence': ?confidence,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [ParseHint].
  static const SchemanticType<ParseHint> $schema = _ParseHintTypeFactory();

  /// What the hint points at.
  String get kind {
    return _json['kind'] as String;
  }

  /// What the hint points at.
  set kind(String value) {
    _json['kind'] = value;
  }

  /// The matched text span.
  String? get span {
    return _json['span'] as String?;
  }

  /// The matched text span.
  set span(String? value) {
    if (value == null) {
      _json.remove('span');
    } else {
      _json['span'] = value;
    }
  }

  /// The resolved id (account, person or category), when resolved.
  String? get id {
    return _json['id'] as String?;
  }

  /// The resolved id (account, person or category), when resolved.
  set id(String? value) {
    if (value == null) {
      _json.remove('id');
    } else {
      _json['id'] = value;
    }
  }

  /// The resolved value for `who` hints (`me`, `partner`, `joint`).
  String? get who {
    return _json['who'] as String?;
  }

  /// The resolved value for `who` hints (`me`, `partner`, `joint`).
  set who(String? value) {
    if (value == null) {
      _json.remove('who');
    } else {
      _json['who'] = value;
    }
  }

  /// Confidence of the match, 0 to 1.
  double? get confidence {
    return (_json['confidence'] as num?)?.toDouble();
  }

  /// Confidence of the match, 0 to 1.
  set confidence(double? value) {
    if (value == null) {
      _json.remove('confidence');
    } else {
      _json['confidence'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [ParseHint] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _ParseHintTypeFactory extends SchemanticType<ParseHint> {
  const _ParseHintTypeFactory();

  @override
  ParseHint parse(Object? json) {
    return ParseHint._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'ParseHint',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'An account, person, category or who hint.',
      'properties': <String, Object?>{
        'kind': <String, Object?>{
          'type': 'string',
          'enum': ['account', 'person', 'category', 'who'],
        },
        'span': <String, Object?>{'type': 'string'},
        'id': <String, Object?>{'type': 'string'},
        'who': <String, Object?>{
          'type': 'string',
          'enum': ['me', 'partner', 'joint'],
        },
        'confidence': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
      },
      'required': ['kind'],
    },
    dependencies: [],
  );
}

/// A learned rule that matched (DATA_MODEL 2.12).
base class RuleHit {
  /// Creates a [RuleHit] from a JSON map.
  factory RuleHit.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  RuleHit._(this._json);

  RuleHit({
    required String ruleId,
    required String field,
    required String value,
    double? confidence,
  }) {
    _json = {
      'ruleId': ruleId,
      'field': field,
      'value': value,
      'confidence': ?confidence,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [RuleHit].
  static const SchemanticType<RuleHit> $schema = _RuleHitTypeFactory();

  /// The rule's id.
  String get ruleId {
    return _json['ruleId'] as String;
  }

  /// The rule's id.
  set ruleId(String value) {
    _json['ruleId'] = value;
  }

  /// The field the rule sets.
  String get field {
    return _json['field'] as String;
  }

  /// The field the rule sets.
  set field(String value) {
    _json['field'] = value;
  }

  /// The value the rule sets (an id, a `who` value or an intent).
  String get value {
    return _json['value'] as String;
  }

  /// The value the rule sets (an id, a `who` value or an intent).
  set value(String value) {
    _json['value'] = value;
  }

  /// Confidence; rule hits are 0.99 (AI_PIPELINE 5).
  double? get confidence {
    return (_json['confidence'] as num?)?.toDouble();
  }

  /// Confidence; rule hits are 0.99 (AI_PIPELINE 5).
  set confidence(double? value) {
    if (value == null) {
      _json.remove('confidence');
    } else {
      _json['confidence'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [RuleHit] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _RuleHitTypeFactory extends SchemanticType<RuleHit> {
  const _RuleHitTypeFactory();

  @override
  RuleHit parse(Object? json) {
    return RuleHit._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'RuleHit',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'A learned rule that matched the message.',
      'properties': <String, Object?>{
        'ruleId': <String, Object?>{'type': 'string'},
        'field': <String, Object?>{
          'type': 'string',
          'enum': ['categoryId', 'accountId', 'who', 'intent'],
        },
        'value': <String, Object?>{'type': 'string'},
        'confidence': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
      },
      'required': ['ruleId', 'field', 'value'],
    },
    dependencies: [],
  );
}

/// The router's complexity signals (AI_PIPELINE 2).
base class ComplexitySignals {
  /// Creates a [ComplexitySignals] from a JSON map.
  factory ComplexitySignals.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  ComplexitySignals._(this._json);

  ComplexitySignals({
    int? amountCount,
    bool? hasConjunction,
    bool? isQuestion,
    bool? isCommand,
    bool? hasPersonTransfer,
    List<String>? unresolved,
    String? attachment,
  }) {
    _json = {
      'amountCount': ?amountCount,
      'hasConjunction': ?hasConjunction,
      'isQuestion': ?isQuestion,
      'isCommand': ?isCommand,
      'hasPersonTransfer': ?hasPersonTransfer,
      'unresolved': ?unresolved,
      'attachment': ?attachment,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [ComplexitySignals].
  static const SchemanticType<ComplexitySignals> $schema =
      _ComplexitySignalsTypeFactory();

  /// Number of amounts found.
  int? get amountCount {
    return (_json['amountCount'] as num?)?.toInt();
  }

  /// Number of amounts found.
  set amountCount(int? value) {
    if (value == null) {
      _json.remove('amountCount');
    } else {
      _json['amountCount'] = value;
    }
  }

  /// A conjunction joins clauses that each hold an amount or a verb.
  bool? get hasConjunction {
    return _json['hasConjunction'] as bool?;
  }

  /// A conjunction joins clauses that each hold an amount or a verb.
  set hasConjunction(bool? value) {
    if (value == null) {
      _json.remove('hasConjunction');
    } else {
      _json['hasConjunction'] = value;
    }
  }

  /// The message asks about data.
  bool? get isQuestion {
    return _json['isQuestion'] as bool?;
  }

  /// The message asks about data.
  set isQuestion(bool? value) {
    if (value == null) {
      _json.remove('isQuestion');
    } else {
      _json['isQuestion'] = value;
    }
  }

  /// The message is a command (delete, change, undo, set budget, new goal).
  bool? get isCommand {
    return _json['isCommand'] as bool?;
  }

  /// The message is a command (delete, change, undo, set budget, new goal).
  set isCommand(bool? value) {
    if (value == null) {
      _json.remove('isCommand');
    } else {
      _json['isCommand'] = value;
    }
  }

  /// Money went to or came from a named person.
  bool? get hasPersonTransfer {
    return _json['hasPersonTransfer'] as bool?;
  }

  /// Money went to or came from a named person.
  set hasPersonTransfer(bool? value) {
    if (value == null) {
      _json.remove('hasPersonTransfer');
    } else {
      _json['hasPersonTransfer'] = value;
    }
  }

  /// Required fields still missing after rules.
  List<String>? get unresolved {
    return (_json['unresolved'] as List?)?.cast<String>();
  }

  /// Required fields still missing after rules.
  set unresolved(List<String>? value) {
    if (value == null) {
      _json.remove('unresolved');
    } else {
      _json['unresolved'] = value;
    }
  }

  /// The attachment type.
  String? get attachment {
    return _json['attachment'] as String?;
  }

  /// The attachment type.
  set attachment(String? value) {
    if (value == null) {
      _json.remove('attachment');
    } else {
      _json['attachment'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [ComplexitySignals] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _ComplexitySignalsTypeFactory
    extends SchemanticType<ComplexitySignals> {
  const _ComplexitySignalsTypeFactory();

  @override
  ComplexitySignals parse(Object? json) {
    return ComplexitySignals._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'ComplexitySignals',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Complexity signals used by the router.',
      'properties': <String, Object?>{
        'amountCount': <String, Object?>{'type': 'integer', 'minimum': 0},
        'hasConjunction': <String, Object?>{'type': 'boolean'},
        'isQuestion': <String, Object?>{'type': 'boolean'},
        'isCommand': <String, Object?>{'type': 'boolean'},
        'hasPersonTransfer': <String, Object?>{'type': 'boolean'},
        'unresolved': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
        'attachment': <String, Object?>{
          'type': 'string',
          'enum': ['none', 'audio', 'image'],
        },
      },
    },
    dependencies: [],
  );
}
