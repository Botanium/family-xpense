// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entry_draft.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

/// One proposed money entry, before the user saves it (AI_PIPELINE 8).
///
/// Produced by the parser, rules, the on-device model, the Decisions API or
/// the agent, and rendered by the `EntryList` card. Everything except [id]
/// and [intent] is nullable so partial drafts and reloaded session state
/// parse without throwing.
base class EntryDraft {
  /// Creates a [EntryDraft] from a JSON map.
  factory EntryDraft.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  EntryDraft._(this._json);

  EntryDraft({
    required String id,
    required String intent,
    int? amountMinor,
    String? currency,
    String? accountId,
    String? toAccountId,
    String? categoryId,
    String? who,
    String? occurredOn,
    String? occurredTime,
    String? title,
    String? note,
    String? personName,
    String? personId,
    String? loanId,
    String? goalId,
    FxQuote? fx,
    DraftConfidence? confidence,
    List<String>? guessed,
    List<String>? missing,
    DuplicateHint? duplicate,
    RecurringHint? recurring,
    String? origin,
  }) {
    _json = {
      'id': id,
      'intent': intent,
      'amountMinor': ?amountMinor,
      'currency': ?currency,
      'accountId': ?accountId,
      'toAccountId': ?toAccountId,
      'categoryId': ?categoryId,
      'who': ?who,
      'occurredOn': ?occurredOn,
      'occurredTime': ?occurredTime,
      'title': ?title,
      'note': ?note,
      'personName': ?personName,
      'personId': ?personId,
      'loanId': ?loanId,
      'goalId': ?goalId,
      'fx': ?fx?.toJson(),
      'confidence': ?confidence?.toJson(),
      'guessed': ?guessed,
      'missing': ?missing,
      'duplicate': ?duplicate?.toJson(),
      'recurring': ?recurring?.toJson(),
      'origin': ?origin,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [EntryDraft].
  static const SchemanticType<EntryDraft> $schema = _EntryDraftTypeFactory();

  /// Draft id, unique within the surface.
  String get id {
    return _json['id'] as String;
  }

  /// Draft id, unique within the surface.
  set id(String value) {
    _json['id'] = value;
  }

  /// The money intent; never `question`, `command` or `other`.
  String get intent {
    return _json['intent'] as String;
  }

  /// The money intent; never `question`, `command` or `other`.
  set intent(String value) {
    _json['intent'] = value;
  }

  /// Amount in minor units of [currency]; always positive.
  int? get amountMinor {
    return (_json['amountMinor'] as num?)?.toInt();
  }

  /// Amount in minor units of [currency]; always positive.
  set amountMinor(int? value) {
    if (value == null) {
      _json.remove('amountMinor');
    } else {
      _json['amountMinor'] = value;
    }
  }

  /// ISO currency code; equals the account's currency.
  String? get currency {
    return _json['currency'] as String?;
  }

  /// ISO currency code; equals the account's currency.
  set currency(String? value) {
    if (value == null) {
      _json.remove('currency');
    } else {
      _json['currency'] = value;
    }
  }

  /// The account money leaves (or enters, for income-like intents).
  String? get accountId {
    return _json['accountId'] as String?;
  }

  /// The account money leaves (or enters, for income-like intents).
  set accountId(String? value) {
    if (value == null) {
      _json.remove('accountId');
    } else {
      _json['accountId'] = value;
    }
  }

  /// The destination account of a transfer or savings move.
  String? get toAccountId {
    return _json['toAccountId'] as String?;
  }

  /// The destination account of a transfer or savings move.
  set toAccountId(String? value) {
    if (value == null) {
      _json.remove('toAccountId');
    } else {
      _json['toAccountId'] = value;
    }
  }

  /// The category id (required for expense and income before saving).
  String? get categoryId {
    return _json['categoryId'] as String?;
  }

  /// The category id (required for expense and income before saving).
  set categoryId(String? value) {
    if (value == null) {
      _json.remove('categoryId');
    } else {
      _json['categoryId'] = value;
    }
  }

  /// Whose entry this is.
  String? get who {
    return _json['who'] as String?;
  }

  /// Whose entry this is.
  set who(String? value) {
    if (value == null) {
      _json.remove('who');
    } else {
      _json['who'] = value;
    }
  }

  /// Household-local date, `YYYY-MM-DD`.
  String? get occurredOn {
    return _json['occurredOn'] as String?;
  }

  /// Household-local date, `YYYY-MM-DD`.
  set occurredOn(String? value) {
    if (value == null) {
      _json.remove('occurredOn');
    } else {
      _json['occurredOn'] = value;
    }
  }

  /// Household-local time, `HH:mm`.
  String? get occurredTime {
    return _json['occurredTime'] as String?;
  }

  /// Household-local time, `HH:mm`.
  set occurredTime(String? value) {
    if (value == null) {
      _json.remove('occurredTime');
    } else {
      _json['occurredTime'] = value;
    }
  }

  /// Merchant or short label.
  String? get title {
    return _json['title'] as String?;
  }

  /// Merchant or short label.
  set title(String? value) {
    if (value == null) {
      _json.remove('title');
    } else {
      _json['title'] = value;
    }
  }

  /// Free-text note.
  String? get note {
    return _json['note'] as String?;
  }

  /// Free-text note.
  set note(String? value) {
    if (value == null) {
      _json.remove('note');
    } else {
      _json['note'] = value;
    }
  }

  /// Counterparty name as spoken, for loans and repayments.
  String? get personName {
    return _json['personName'] as String?;
  }

  /// Counterparty name as spoken, for loans and repayments.
  set personName(String? value) {
    if (value == null) {
      _json.remove('personName');
    } else {
      _json['personName'] = value;
    }
  }

  /// Resolved counterparty id.
  String? get personId {
    return _json['personId'] as String?;
  }

  /// Resolved counterparty id.
  set personId(String? value) {
    if (value == null) {
      _json.remove('personId');
    } else {
      _json['personId'] = value;
    }
  }

  /// The loan this entry belongs to.
  String? get loanId {
    return _json['loanId'] as String?;
  }

  /// The loan this entry belongs to.
  set loanId(String? value) {
    if (value == null) {
      _json.remove('loanId');
    } else {
      _json['loanId'] = value;
    }
  }

  /// The goal of a savings move.
  String? get goalId {
    return _json['goalId'] as String?;
  }

  /// The goal of a savings move.
  set goalId(String? value) {
    if (value == null) {
      _json.remove('goalId');
    } else {
      _json['goalId'] = value;
    }
  }

  /// The conversion into the household base currency.
  FxQuote? get fx {
    return _json['fx'] == null
        ? null
        : FxQuote.fromJson(_json['fx'] as Map<String, dynamic>);
  }

  /// The conversion into the household base currency.
  set fx(FxQuote? value) {
    if (value == null) {
      _json.remove('fx');
    } else {
      _json['fx'] = value.toJson();
    }
  }

  /// Per-field confidence, 0 to 1.
  DraftConfidence? get confidence {
    return _json['confidence'] == null
        ? null
        : DraftConfidence.fromJson(_json['confidence'] as Map<String, dynamic>);
  }

  /// Per-field confidence, 0 to 1.
  set confidence(DraftConfidence? value) {
    if (value == null) {
      _json.remove('confidence');
    } else {
      _json['confidence'] = value.toJson();
    }
  }

  /// Field names shown with the "Guessed" badge.
  List<String>? get guessed {
    return (_json['guessed'] as List?)?.cast<String>();
  }

  /// Field names shown with the "Guessed" badge.
  set guessed(List<String>? value) {
    if (value == null) {
      _json.remove('guessed');
    } else {
      _json['guessed'] = value;
    }
  }

  /// Required field names still empty.
  List<String>? get missing {
    return (_json['missing'] as List?)?.cast<String>();
  }

  /// Required field names still empty.
  set missing(List<String>? value) {
    if (value == null) {
      _json.remove('missing');
    } else {
      _json['missing'] = value;
    }
  }

  /// A possible duplicate of a saved entry.
  DuplicateHint? get duplicate {
    return _json['duplicate'] == null
        ? null
        : DuplicateHint.fromJson(_json['duplicate'] as Map<String, dynamic>);
  }

  /// A possible duplicate of a saved entry.
  set duplicate(DuplicateHint? value) {
    if (value == null) {
      _json.remove('duplicate');
    } else {
      _json['duplicate'] = value.toJson();
    }
  }

  /// A guess that this entry repeats.
  RecurringHint? get recurring {
    return _json['recurring'] == null
        ? null
        : RecurringHint.fromJson(_json['recurring'] as Map<String, dynamic>);
  }

  /// A guess that this entry repeats.
  set recurring(RecurringHint? value) {
    if (value == null) {
      _json.remove('recurring');
    } else {
      _json['recurring'] = value.toJson();
    }
  }

  /// The step that produced this draft.
  String? get origin {
    return _json['origin'] as String?;
  }

  /// The step that produced this draft.
  set origin(String? value) {
    if (value == null) {
      _json.remove('origin');
    } else {
      _json['origin'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [EntryDraft] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _EntryDraftTypeFactory extends SchemanticType<EntryDraft> {
  const _EntryDraftTypeFactory();

  @override
  EntryDraft parse(Object? json) {
    return EntryDraft._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'EntryDraft',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'A proposed money entry awaiting confirmation.',
      'properties': <String, Object?>{
        'id': <String, Object?>{
          'type': 'string',
          'description': 'Draft id, unique within the surface.',
        },
        'intent': <String, Object?>{
          'type': 'string',
          'enum': [
            'expense',
            'income',
            'transfer',
            'savings_move',
            'loan_given',
            'loan_taken',
            'repayment_received',
            'repayment_made',
            'adjustment',
          ],
        },
        'amountMinor': <String, Object?>{
          'type': 'integer',
          'description':
              'Amount in minor units of currency (cents, whole dinars).',
          'minimum': 1,
        },
        'currency': <String, Object?>{
          'type': 'string',
          'enum': ['USD', 'IQD'],
        },
        'accountId': <String, Object?>{'type': 'string'},
        'toAccountId': <String, Object?>{'type': 'string'},
        'categoryId': <String, Object?>{'type': 'string'},
        'who': <String, Object?>{
          'type': 'string',
          'enum': ['me', 'partner', 'joint'],
        },
        'occurredOn': <String, Object?>{
          'type': 'string',
          'description': 'Household-local date, YYYY-MM-DD.',
        },
        'occurredTime': <String, Object?>{
          'type': 'string',
          'description': 'Household-local time, HH:mm.',
        },
        'title': <String, Object?>{'type': 'string', 'maxLength': 80},
        'note': <String, Object?>{'type': 'string', 'maxLength': 500},
        'personName': <String, Object?>{'type': 'string'},
        'personId': <String, Object?>{'type': 'string'},
        'loanId': <String, Object?>{'type': 'string'},
        'goalId': <String, Object?>{'type': 'string'},
        'fx': <String, Object?>{r'$ref': r'#/$defs/FxQuote'},
        'confidence': <String, Object?>{r'$ref': r'#/$defs/DraftConfidence'},
        'guessed': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
        'missing': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
        'duplicate': <String, Object?>{r'$ref': r'#/$defs/DuplicateHint'},
        'recurring': <String, Object?>{r'$ref': r'#/$defs/RecurringHint'},
        'origin': <String, Object?>{
          'type': 'string',
          'enum': ['parser', 'rule', 'on_device', 'decisions', 'agent'],
        },
      },
      'required': ['id', 'intent'],
    },
    dependencies: [
      FxQuote.$schema,
      DraftConfidence.$schema,
      DuplicateHint.$schema,
      RecurringHint.$schema,
    ],
  );
}

/// The FX conversion stored with an entry (`transactions.fx`, DATA_MODEL 1).
base class FxQuote {
  /// Creates a [FxQuote] from a JSON map.
  factory FxQuote.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  FxQuote._(this._json);

  FxQuote({
    required String pair,
    required String pairRate,
    String? source,
    String? asOf,
    int? baseAmountMinor,
  }) {
    _json = {
      'pair': pair,
      'pairRate': pairRate,
      'source': ?source,
      'asOf': ?asOf,
      'baseAmountMinor': ?baseAmountMinor,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [FxQuote].
  static const SchemanticType<FxQuote> $schema = _FxQuoteTypeFactory();

  /// Market-convention pair, for example `USD/IQD`.
  String get pair {
    return _json['pair'] as String;
  }

  /// Market-convention pair, for example `USD/IQD`.
  set pair(String value) {
    _json['pair'] = value;
  }

  /// The rate as a decimal string, for example `"1520"`; never a float.
  String get pairRate {
    return _json['pairRate'] as String;
  }

  /// The rate as a decimal string, for example `"1520"`; never a float.
  set pairRate(String value) {
    _json['pairRate'] = value;
  }

  /// The household's label for the rate.
  String? get source {
    return _json['source'] as String?;
  }

  /// The household's label for the rate.
  set source(String? value) {
    if (value == null) {
      _json.remove('source');
    } else {
      _json['source'] = value;
    }
  }

  /// The household-local day the rate is for, `YYYY-MM-DD`.
  String? get asOf {
    return _json['asOf'] as String?;
  }

  /// The household-local day the rate is for, `YYYY-MM-DD`.
  set asOf(String? value) {
    if (value == null) {
      _json.remove('asOf');
    } else {
      _json['asOf'] = value;
    }
  }

  /// The amount in the household base currency, rounded half-even once.
  int? get baseAmountMinor {
    return (_json['baseAmountMinor'] as num?)?.toInt();
  }

  /// The amount in the household base currency, rounded half-even once.
  set baseAmountMinor(int? value) {
    if (value == null) {
      _json.remove('baseAmountMinor');
    } else {
      _json['baseAmountMinor'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [FxQuote] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _FxQuoteTypeFactory extends SchemanticType<FxQuote> {
  const _FxQuoteTypeFactory();

  @override
  FxQuote parse(Object? json) {
    return FxQuote._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'FxQuote',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Exchange rate used to compute the base amount.',
      'properties': <String, Object?>{
        'pair': <String, Object?>{
          'type': 'string',
          'description': 'Market-convention pair, for example USD/IQD.',
        },
        'pairRate': <String, Object?>{
          'type': 'string',
          'description': 'Rate as a decimal string, for example "1520".',
        },
        'source': <String, Object?>{
          'type': 'string',
          'enum': ['official', 'market', 'manual'],
        },
        'asOf': <String, Object?>{
          'type': 'string',
          'description': 'Day of the rate, YYYY-MM-DD.',
        },
        'baseAmountMinor': <String, Object?>{
          'type': 'integer',
          'description': 'Amount in base-currency minor units.',
        },
      },
      'required': ['pair', 'pairRate'],
    },
    dependencies: [],
  );
}

/// Confidence of a draft's classified fields, each 0 to 1.
base class DraftConfidence {
  /// Creates a [DraftConfidence] from a JSON map.
  factory DraftConfidence.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  DraftConfidence._(this._json);

  DraftConfidence({
    double? intent,
    double? category,
    double? account,
    double? who,
  }) {
    _json = {
      'intent': ?intent,
      'category': ?category,
      'account': ?account,
      'who': ?who,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [DraftConfidence].
  static const SchemanticType<DraftConfidence> $schema =
      _DraftConfidenceTypeFactory();

  /// Confidence in the intent.
  double? get intent {
    return (_json['intent'] as num?)?.toDouble();
  }

  /// Confidence in the intent.
  set intent(double? value) {
    if (value == null) {
      _json.remove('intent');
    } else {
      _json['intent'] = value;
    }
  }

  /// Confidence in the category.
  double? get category {
    return (_json['category'] as num?)?.toDouble();
  }

  /// Confidence in the category.
  set category(double? value) {
    if (value == null) {
      _json.remove('category');
    } else {
      _json['category'] = value;
    }
  }

  /// Confidence in the account.
  double? get account {
    return (_json['account'] as num?)?.toDouble();
  }

  /// Confidence in the account.
  set account(double? value) {
    if (value == null) {
      _json.remove('account');
    } else {
      _json['account'] = value;
    }
  }

  /// Confidence in who the entry belongs to.
  double? get who {
    return (_json['who'] as num?)?.toDouble();
  }

  /// Confidence in who the entry belongs to.
  set who(double? value) {
    if (value == null) {
      _json.remove('who');
    } else {
      _json['who'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [DraftConfidence] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _DraftConfidenceTypeFactory extends SchemanticType<DraftConfidence> {
  const _DraftConfidenceTypeFactory();

  @override
  DraftConfidence parse(Object? json) {
    return DraftConfidence._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'DraftConfidence',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Per-field confidence, 0 to 1.',
      'properties': <String, Object?>{
        'intent': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
        'category': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
        'account': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
        'who': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 1},
      },
    },
    dependencies: [],
  );
}

/// A saved entry this draft may duplicate.
base class DuplicateHint {
  /// Creates a [DuplicateHint] from a JSON map.
  factory DuplicateHint.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  DuplicateHint._(this._json);

  DuplicateHint({required String txnId, double? probability}) {
    _json = {'txnId': txnId, 'probability': ?probability};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [DuplicateHint].
  static const SchemanticType<DuplicateHint> $schema =
      _DuplicateHintTypeFactory();

  /// The saved transaction's id.
  String get txnId {
    return _json['txnId'] as String;
  }

  /// The saved transaction's id.
  set txnId(String value) {
    _json['txnId'] = value;
  }

  /// Probability that the draft is the same event, 0 to 1.
  double? get probability {
    return (_json['probability'] as num?)?.toDouble();
  }

  /// Probability that the draft is the same event, 0 to 1.
  set probability(double? value) {
    if (value == null) {
      _json.remove('probability');
    } else {
      _json['probability'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [DuplicateHint] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _DuplicateHintTypeFactory extends SchemanticType<DuplicateHint> {
  const _DuplicateHintTypeFactory();

  @override
  DuplicateHint parse(Object? json) {
    return DuplicateHint._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'DuplicateHint',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'A saved entry this draft may duplicate.',
      'properties': <String, Object?>{
        'txnId': <String, Object?>{'type': 'string'},
        'probability': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
      },
      'required': ['txnId'],
    },
    dependencies: [],
  );
}

/// A guess that the entry repeats (`recurring.cadence`, DATA_MODEL 2.11).
base class RecurringHint {
  /// Creates a [RecurringHint] from a JSON map.
  factory RecurringHint.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  RecurringHint._(this._json);

  RecurringHint({
    double? probability,
    String? unit,
    int? interval,
    int? dayOfMonth,
    int? weekday,
    String? recurringId,
  }) {
    _json = {
      'probability': ?probability,
      'unit': ?unit,
      'interval': ?interval,
      'dayOfMonth': ?dayOfMonth,
      'weekday': ?weekday,
      'recurringId': ?recurringId,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [RecurringHint].
  static const SchemanticType<RecurringHint> $schema =
      _RecurringHintTypeFactory();

  /// Probability that the entry repeats, 0 to 1.
  double? get probability {
    return (_json['probability'] as num?)?.toDouble();
  }

  /// Probability that the entry repeats, 0 to 1.
  set probability(double? value) {
    if (value == null) {
      _json.remove('probability');
    } else {
      _json['probability'] = value;
    }
  }

  /// The repeat unit.
  String? get unit {
    return _json['unit'] as String?;
  }

  /// The repeat unit.
  set unit(String? value) {
    if (value == null) {
      _json.remove('unit');
    } else {
      _json['unit'] = value;
    }
  }

  /// Repeat every this many units.
  int? get interval {
    return (_json['interval'] as num?)?.toInt();
  }

  /// Repeat every this many units.
  set interval(int? value) {
    if (value == null) {
      _json.remove('interval');
    } else {
      _json['interval'] = value;
    }
  }

  /// Day of the month, for monthly cadence.
  int? get dayOfMonth {
    return (_json['dayOfMonth'] as num?)?.toInt();
  }

  /// Day of the month, for monthly cadence.
  set dayOfMonth(int? value) {
    if (value == null) {
      _json.remove('dayOfMonth');
    } else {
      _json['dayOfMonth'] = value;
    }
  }

  /// ISO weekday (1 is Monday), for weekly cadence.
  int? get weekday {
    return (_json['weekday'] as num?)?.toInt();
  }

  /// ISO weekday (1 is Monday), for weekly cadence.
  set weekday(int? value) {
    if (value == null) {
      _json.remove('weekday');
    } else {
      _json['weekday'] = value;
    }
  }

  /// An existing recurring template this matches, if any.
  String? get recurringId {
    return _json['recurringId'] as String?;
  }

  /// An existing recurring template this matches, if any.
  set recurringId(String? value) {
    if (value == null) {
      _json.remove('recurringId');
    } else {
      _json['recurringId'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [RecurringHint] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _RecurringHintTypeFactory extends SchemanticType<RecurringHint> {
  const _RecurringHintTypeFactory();

  @override
  RecurringHint parse(Object? json) {
    return RecurringHint._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'RecurringHint',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'A guess that this entry repeats.',
      'properties': <String, Object?>{
        'probability': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
        'unit': <String, Object?>{
          'type': 'string',
          'enum': ['month', 'week'],
        },
        'interval': <String, Object?>{'type': 'integer', 'minimum': 1},
        'dayOfMonth': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 31,
        },
        'weekday': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 7,
        },
        'recurringId': <String, Object?>{'type': 'string'},
      },
    },
    dependencies: [],
  );
}
