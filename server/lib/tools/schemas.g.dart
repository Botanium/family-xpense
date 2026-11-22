// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schemas.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

/// One money event the model found in the user's message.
base class ProposedEntry {
  /// Creates a [ProposedEntry] from a JSON map.
  factory ProposedEntry.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  ProposedEntry._(this._json);

  ProposedEntry({
    required String intent,
    String? amount,
    String? currency,
    required String text,
    String? dateWords,
    String? accountHint,
    String? toAccountHint,
    String? categoryHint,
    String? person,
    String? who,
    String? title,
  }) {
    _json = {
      'intent': intent,
      'amount': ?amount,
      'currency': ?currency,
      'text': text,
      'dateWords': ?dateWords,
      'accountHint': ?accountHint,
      'toAccountHint': ?toAccountHint,
      'categoryHint': ?categoryHint,
      'person': ?person,
      'who': ?who,
      'title': ?title,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [ProposedEntry].
  static const SchemanticType<ProposedEntry> $schema =
      _ProposedEntryTypeFactory();

  /// The money intent.
  String get intent {
    return _json['intent'] as String;
  }

  /// The money intent.
  set intent(String value) {
    _json['intent'] = value;
  }

  /// The amount exactly as written, in major units.
  String? get amount {
    return _json['amount'] as String?;
  }

  /// The amount exactly as written, in major units.
  set amount(String? value) {
    if (value == null) {
      _json.remove('amount');
    } else {
      _json['amount'] = value;
    }
  }

  /// The currency the user named.
  String? get currency {
    return _json['currency'] as String?;
  }

  /// The currency the user named.
  set currency(String? value) {
    if (value == null) {
      _json.remove('currency');
    } else {
      _json['currency'] = value;
    }
  }

  /// The words of the message about this entry.
  String get text {
    return _json['text'] as String;
  }

  /// The words of the message about this entry.
  set text(String value) {
    _json['text'] = value;
  }

  /// Date words as written.
  String? get dateWords {
    return _json['dateWords'] as String?;
  }

  /// Date words as written.
  set dateWords(String? value) {
    if (value == null) {
      _json.remove('dateWords');
    } else {
      _json['dateWords'] = value;
    }
  }

  /// Account words as written.
  String? get accountHint {
    return _json['accountHint'] as String?;
  }

  /// Account words as written.
  set accountHint(String? value) {
    if (value == null) {
      _json.remove('accountHint');
    } else {
      _json['accountHint'] = value;
    }
  }

  /// Destination account words for a transfer or savings move.
  String? get toAccountHint {
    return _json['toAccountHint'] as String?;
  }

  /// Destination account words for a transfer or savings move.
  set toAccountHint(String? value) {
    if (value == null) {
      _json.remove('toAccountHint');
    } else {
      _json['toAccountHint'] = value;
    }
  }

  /// Category words or a category slug.
  String? get categoryHint {
    return _json['categoryHint'] as String?;
  }

  /// Category words or a category slug.
  set categoryHint(String? value) {
    if (value == null) {
      _json.remove('categoryHint');
    } else {
      _json['categoryHint'] = value;
    }
  }

  /// The other person, for loans, repayments and gifts.
  String? get person {
    return _json['person'] as String?;
  }

  /// The other person, for loans, repayments and gifts.
  set person(String? value) {
    if (value == null) {
      _json.remove('person');
    } else {
      _json['person'] = value;
    }
  }

  /// Whose money it is, when the message says so.
  String? get who {
    return _json['who'] as String?;
  }

  /// Whose money it is, when the message says so.
  set who(String? value) {
    if (value == null) {
      _json.remove('who');
    } else {
      _json['who'] = value;
    }
  }

  /// A merchant or short label.
  String? get title {
    return _json['title'] as String?;
  }

  /// A merchant or short label.
  set title(String? value) {
    if (value == null) {
      _json.remove('title');
    } else {
      _json['title'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [ProposedEntry] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _ProposedEntryTypeFactory extends SchemanticType<ProposedEntry> {
  const _ProposedEntryTypeFactory();

  @override
  ProposedEntry parse(Object? json) {
    return ProposedEntry._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'ProposedEntry',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'One money event found in the message.',
      'properties': <String, Object?>{
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
        'amount': <String, Object?>{
          'type': 'string',
          'description': 'The amount exactly as the user wrote it, in major units, digits only, e.g. "3200", "12.50", "25000". Omit if the user gave none. Never compute or convert it.',
        },
        'currency': <String, Object?>{
          'type': 'string',
          'enum': ['USD', 'IQD'],
        },
        'text': <String, Object?>{
          'type': 'string',
          'description': 'The words of the message about this entry only, copied verbatim, e.g. "paid rent 1400".',
          'maxLength': 300,
        },
        'dateWords': <String, Object?>{
          'type': 'string',
          'description':
              'Date words as written, e.g. "yesterday", "on the 3rd".',
        },
        'accountHint': <String, Object?>{
          'type': 'string',
          'description': 'Account words as written, e.g. "the joint card".',
        },
        'toAccountHint': <String, Object?>{
          'type': 'string',
          'description': 'Destination account words, for transfers.',
        },
        'categoryHint': <String, Object?>{
          'type': 'string',
          'description': 'Category words or slug, e.g. "groceries".',
        },
        'person': <String, Object?>{
          'type': 'string',
          'description': 'The other person, as named.',
        },
        'who': <String, Object?>{
          'type': 'string',
          'enum': ['me', 'partner', 'joint'],
        },
        'title': <String, Object?>{
          'type': 'string',
          'description': 'Merchant or short label, e.g. "Rent".',
        },
      },
      'required': ['intent', 'text'],
    },
    dependencies: [],
  );
}

/// `prepareEntries` input.
base class PrepareEntriesInput {
  /// Creates a [PrepareEntriesInput] from a JSON map.
  factory PrepareEntriesInput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  PrepareEntriesInput._(this._json);

  PrepareEntriesInput({required List<ProposedEntry> entries}) {
    _json = {'entries': entries.map((e) => e.toJson()).toList()};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [PrepareEntriesInput].
  static const SchemanticType<PrepareEntriesInput> $schema =
      _PrepareEntriesInputTypeFactory();

  /// The entries; the whole set replaces any earlier drafts of this turn.
  List<ProposedEntry> get entries {
    return (_json['entries'] as List)
        .map((e) => ProposedEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The entries; the whole set replaces any earlier drafts of this turn.
  set entries(List<ProposedEntry> value) {
    _json['entries'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [PrepareEntriesInput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _PrepareEntriesInputTypeFactory
    extends SchemanticType<PrepareEntriesInput> {
  const _PrepareEntriesInputTypeFactory();

  @override
  PrepareEntriesInput parse(Object? json) {
    return PrepareEntriesInput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'PrepareEntriesInput',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Every money event in the message, in order.',
      'properties': <String, Object?>{
        'entries': <String, Object?>{
          'type': 'array',
          'description': 'All entries of the message. Calling again replaces the whole set.',
          'items': <String, Object?>{r'$ref': r'#/$defs/ProposedEntry'},
        },
      },
      'required': ['entries'],
    },
    dependencies: [ProposedEntry.$schema],
  );
}

/// `prepareEntries` output.
base class PrepareEntriesOutput {
  /// Creates a [PrepareEntriesOutput] from a JSON map.
  factory PrepareEntriesOutput.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  PrepareEntriesOutput._(this._json);

  PrepareEntriesOutput({
    required List<EntryDraft> drafts,
    FollowUp? ask,
    List<String>? notes,
  }) {
    _json = {
      'drafts': drafts.map((e) => e.toJson()).toList(),
      'ask': ?ask?.toJson(),
      'notes': ?notes,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [PrepareEntriesOutput].
  static const SchemanticType<PrepareEntriesOutput> $schema =
      _PrepareEntriesOutputTypeFactory();

  /// The drafts, ready for `$/drafts`.
  List<EntryDraft> get drafts {
    return (_json['drafts'] as List)
        .map((e) => EntryDraft.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The drafts, ready for `$/drafts`.
  set drafts(List<EntryDraft> value) {
    _json['drafts'] = value.map((e) => e.toJson()).toList();
  }

  /// The first follow-up to ask, if any: `{draftId, field}`.
  FollowUp? get ask {
    return _json['ask'] == null
        ? null
        : FollowUp.fromJson(_json['ask'] as Map<String, dynamic>);
  }

  /// The first follow-up to ask, if any: `{draftId, field}`.
  set ask(FollowUp? value) {
    if (value == null) {
      _json.remove('ask');
    } else {
      _json['ask'] = value.toJson();
    }
  }

  /// Short notes for the model, e.g. an amount not found in the message.
  List<String>? get notes {
    return (_json['notes'] as List?)?.cast<String>();
  }

  /// Short notes for the model, e.g. an amount not found in the message.
  set notes(List<String>? value) {
    if (value == null) {
      _json.remove('notes');
    } else {
      _json['notes'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [PrepareEntriesOutput] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _PrepareEntriesOutputTypeFactory
    extends SchemanticType<PrepareEntriesOutput> {
  const _PrepareEntriesOutputTypeFactory();

  @override
  PrepareEntriesOutput parse(Object? json) {
    return PrepareEntriesOutput._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'PrepareEntriesOutput',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Checked drafts to render unchanged in one EntryList.',
      'properties': <String, Object?>{
        'drafts': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/EntryDraft'},
        },
        'ask': <String, Object?>{r'$ref': r'#/$defs/FollowUp'},
        'notes': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
      },
      'required': ['drafts'],
    },
    dependencies: [EntryDraft.$schema, FollowUp.$schema],
  );
}

/// The one follow-up question the agent may ask this turn.
base class FollowUp {
  /// Creates a [FollowUp] from a JSON map.
  factory FollowUp.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  FollowUp._(this._json);

  FollowUp({
    required String draftId,
    required int index,
    required String field,
    List<FollowUpOption>? options,
  }) {
    _json = {
      'draftId': draftId,
      'index': index,
      'field': field,
      'options': ?options?.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [FollowUp].
  static const SchemanticType<FollowUp> $schema = _FollowUpTypeFactory();

  /// The draft the question is about.
  String get draftId {
    return _json['draftId'] as String;
  }

  /// The draft the question is about.
  set draftId(String value) {
    _json['draftId'] = value;
  }

  /// The draft's index in `drafts`.
  int get index {
    return (_json['index'] as num).toInt();
  }

  /// The draft's index in `drafts`.
  set index(int value) {
    _json['index'] = value;
  }

  /// The field to ask about.
  String get field {
    return _json['field'] as String;
  }

  /// The field to ask about.
  set field(String value) {
    _json['field'] = value;
  }

  /// Up to three suggested options.
  List<FollowUpOption>? get options {
    return (_json['options'] as List?)
        ?.map((e) => FollowUpOption.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Up to three suggested options.
  set options(List<FollowUpOption>? value) {
    if (value == null) {
      _json.remove('options');
    } else {
      _json['options'] = value.map((e) => e.toJson()).toList();
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [FollowUp] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _FollowUpTypeFactory extends SchemanticType<FollowUp> {
  const _FollowUpTypeFactory();

  @override
  FollowUp parse(Object? json) {
    return FollowUp._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'FollowUp',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'The single follow-up question to ask, if any.',
      'properties': <String, Object?>{
        'draftId': <String, Object?>{'type': 'string'},
        'index': <String, Object?>{'type': 'integer'},
        'field': <String, Object?>{'type': 'string'},
        'options': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/FollowUpOption'},
        },
      },
      'required': ['draftId', 'index', 'field'],
    },
    dependencies: [FollowUpOption.$schema],
  );
}

/// A suggested answer to a follow-up.
base class FollowUpOption {
  /// Creates a [FollowUpOption] from a JSON map.
  factory FollowUpOption.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  FollowUpOption._(this._json);

  FollowUpOption({required String label, required String value, String? hint}) {
    _json = {'label': label, 'value': value, 'hint': ?hint};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [FollowUpOption].
  static const SchemanticType<FollowUpOption> $schema =
      _FollowUpOptionTypeFactory();

  /// Button label.
  String get label {
    return _json['label'] as String;
  }

  /// Button label.
  set label(String value) {
    _json['label'] = value;
  }

  /// The value written to the draft field.
  String get value {
    return _json['value'] as String;
  }

  /// The value written to the draft field.
  set value(String value) {
    _json['value'] = value;
  }

  /// A short hint under the label.
  String? get hint {
    return _json['hint'] as String?;
  }

  /// A short hint under the label.
  set hint(String? value) {
    if (value == null) {
      _json.remove('hint');
    } else {
      _json['hint'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [FollowUpOption] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _FollowUpOptionTypeFactory extends SchemanticType<FollowUpOption> {
  const _FollowUpOptionTypeFactory();

  @override
  FollowUpOption parse(Object? json) {
    return FollowUpOption._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'FollowUpOption',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'A suggested answer.',
      'properties': <String, Object?>{
        'label': <String, Object?>{'type': 'string'},
        'value': <String, Object?>{'type': 'string'},
        'hint': <String, Object?>{'type': 'string'},
      },
      'required': ['label', 'value'],
    },
    dependencies: [],
  );
}

/// `queryLedger` input.
base class LedgerQuery {
  /// Creates a [LedgerQuery] from a JSON map.
  factory LedgerQuery.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  LedgerQuery._(this._json);

  LedgerQuery({
    String? from,
    String? to,
    List<String>? categories,
    List<String>? accountIds,
    String? who,
    List<String>? types,
    String? text,
    String? groupBy,
    String? metric,
    int? limit,
  }) {
    _json = {
      'from': ?from,
      'to': ?to,
      'categories': ?categories,
      'accountIds': ?accountIds,
      'who': ?who,
      'types': ?types,
      'text': ?text,
      'groupBy': ?groupBy,
      'metric': ?metric,
      'limit': ?limit,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [LedgerQuery].
  static const SchemanticType<LedgerQuery> $schema = _LedgerQueryTypeFactory();

  /// First day, inclusive.
  String? get from {
    return _json['from'] as String?;
  }

  /// First day, inclusive.
  set from(String? value) {
    if (value == null) {
      _json.remove('from');
    } else {
      _json['from'] = value;
    }
  }

  /// Last day, inclusive.
  String? get to {
    return _json['to'] as String?;
  }

  /// Last day, inclusive.
  set to(String? value) {
    if (value == null) {
      _json.remove('to');
    } else {
      _json['to'] = value;
    }
  }

  /// Category slugs or ids; a group includes its sub-categories.
  List<String>? get categories {
    return (_json['categories'] as List?)?.cast<String>();
  }

  /// Category slugs or ids; a group includes its sub-categories.
  set categories(List<String>? value) {
    if (value == null) {
      _json.remove('categories');
    } else {
      _json['categories'] = value;
    }
  }

  /// Account ids.
  List<String>? get accountIds {
    return (_json['accountIds'] as List?)?.cast<String>();
  }

  /// Account ids.
  set accountIds(List<String>? value) {
    if (value == null) {
      _json.remove('accountIds');
    } else {
      _json['accountIds'] = value;
    }
  }

  /// Whose entries.
  String? get who {
    return _json['who'] as String?;
  }

  /// Whose entries.
  set who(String? value) {
    if (value == null) {
      _json.remove('who');
    } else {
      _json['who'] = value;
    }
  }

  /// Ledger types; default expense.
  List<String>? get types {
    return (_json['types'] as List?)?.cast<String>();
  }

  /// Ledger types; default expense.
  set types(List<String>? value) {
    if (value == null) {
      _json.remove('types');
    } else {
      _json['types'] = value;
    }
  }

  /// Words to find in title or note.
  String? get text {
    return _json['text'] as String?;
  }

  /// Words to find in title or note.
  set text(String? value) {
    if (value == null) {
      _json.remove('text');
    } else {
      _json['text'] = value;
    }
  }

  /// How to group the rows.
  String? get groupBy {
    return _json['groupBy'] as String?;
  }

  /// How to group the rows.
  set groupBy(String? value) {
    if (value == null) {
      _json.remove('groupBy');
    } else {
      _json['groupBy'] = value;
    }
  }

  /// The metric per row.
  String? get metric {
    return _json['metric'] as String?;
  }

  /// The metric per row.
  set metric(String? value) {
    if (value == null) {
      _json.remove('metric');
    } else {
      _json['metric'] = value;
    }
  }

  /// Maximum rows, largest first (time groups stay in date order).
  int? get limit {
    return (_json['limit'] as num?)?.toInt();
  }

  /// Maximum rows, largest first (time groups stay in date order).
  set limit(int? value) {
    if (value == null) {
      _json.remove('limit');
    } else {
      _json['limit'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [LedgerQuery] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _LedgerQueryTypeFactory extends SchemanticType<LedgerQuery> {
  const _LedgerQueryTypeFactory();

  @override
  LedgerQuery parse(Object? json) {
    return LedgerQuery._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'LedgerQuery',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Filters, grouping and metric over saved entries.',
      'properties': <String, Object?>{
        'from': <String, Object?>{
          'type': 'string',
          'description': 'First day, YYYY-MM-DD. Default: month start.',
        },
        'to': <String, Object?>{
          'type': 'string',
          'description': 'Last day, YYYY-MM-DD. Default: today.',
        },
        'categories': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
        'accountIds': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
        'who': <String, Object?>{
          'type': 'string',
          'enum': ['me', 'partner', 'joint', 'all'],
        },
        'types': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
        'text': <String, Object?>{'type': 'string'},
        'groupBy': <String, Object?>{
          'type': 'string',
          'enum': [
            'none',
            'day',
            'week',
            'month',
            'category',
            'account',
            'who',
          ],
        },
        'metric': <String, Object?>{
          'type': 'string',
          'enum': ['sum', 'count', 'avg'],
        },
        'limit': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
          'maximum': 50,
        },
      },
    },
    dependencies: [],
  );
}

/// `queryLedger` output. Every figure is computed here; the model copies
/// them and never does arithmetic.
base class LedgerResult {
  /// Creates a [LedgerResult] from a JSON map.
  factory LedgerResult.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  LedgerResult._(this._json);

  LedgerResult({
    required String currency,
    required String metric,
    required String from,
    required String to,
    int? totalMinor,
    required int count,
    required List<LedgerRow> rows,
    List<int>? daily,
  }) {
    _json = {
      'currency': currency,
      'metric': metric,
      'from': from,
      'to': to,
      'totalMinor': ?totalMinor,
      'count': count,
      'rows': rows.map((e) => e.toJson()).toList(),
      'daily': ?daily,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [LedgerResult].
  static const SchemanticType<LedgerResult> $schema =
      _LedgerResultTypeFactory();

  /// Base currency of every figure.
  String get currency {
    return _json['currency'] as String;
  }

  /// Base currency of every figure.
  set currency(String value) {
    _json['currency'] = value;
  }

  /// `sum`, `count` or `avg`.
  String get metric {
    return _json['metric'] as String;
  }

  /// `sum`, `count` or `avg`.
  set metric(String value) {
    _json['metric'] = value;
  }

  /// Days covered.
  String get from {
    return _json['from'] as String;
  }

  /// Days covered.
  set from(String value) {
    _json['from'] = value;
  }

  /// Days covered.
  String get to {
    return _json['to'] as String;
  }

  /// Days covered.
  set to(String value) {
    _json['to'] = value;
  }

  /// Sum (or average, for `avg`) over every matching entry, in base-currency
  /// minor units; null for `count`.
  int? get totalMinor {
    return (_json['totalMinor'] as num?)?.toInt();
  }

  /// Sum (or average, for `avg`) over every matching entry, in base-currency
  /// minor units; null for `count`.
  set totalMinor(int? value) {
    if (value == null) {
      _json.remove('totalMinor');
    } else {
      _json['totalMinor'] = value;
    }
  }

  /// Number of matching entries.
  int get count {
    return (_json['count'] as num).toInt();
  }

  /// Number of matching entries.
  set count(int value) {
    _json['count'] = value;
  }

  /// The grouped rows.
  List<LedgerRow> get rows {
    return (_json['rows'] as List)
        .map((e) => LedgerRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The grouped rows.
  set rows(List<LedgerRow> value) {
    _json['rows'] = value.map((e) => e.toJson()).toList();
  }

  /// Daily totals for MiniBars, oldest first (only for `groupBy: day`).
  List<int>? get daily {
    return (_json['daily'] as List?)?.cast<int>();
  }

  /// Daily totals for MiniBars, oldest first (only for `groupBy: day`).
  set daily(List<int>? value) {
    if (value == null) {
      _json.remove('daily');
    } else {
      _json['daily'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [LedgerResult] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _LedgerResultTypeFactory extends SchemanticType<LedgerResult> {
  const _LedgerResultTypeFactory();

  @override
  LedgerResult parse(Object? json) {
    return LedgerResult._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'LedgerResult',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Rows and totals in the household base currency.',
      'properties': <String, Object?>{
        'currency': <String, Object?>{'type': 'string'},
        'metric': <String, Object?>{'type': 'string'},
        'from': <String, Object?>{'type': 'string'},
        'to': <String, Object?>{'type': 'string'},
        'totalMinor': <String, Object?>{'type': 'integer'},
        'count': <String, Object?>{'type': 'integer'},
        'rows': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/LedgerRow'},
        },
        'daily': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'integer'},
        },
      },
      'required': ['currency', 'metric', 'from', 'to', 'count', 'rows'],
    },
    dependencies: [LedgerRow.$schema],
  );
}

/// One grouped row.
base class LedgerRow {
  /// Creates a [LedgerRow] from a JSON map.
  factory LedgerRow.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  LedgerRow._(this._json);

  LedgerRow({
    required String key,
    required String label,
    int? amountMinor,
    required int count,
    double? share,
  }) {
    _json = {
      'key': key,
      'label': label,
      'amountMinor': ?amountMinor,
      'count': count,
      'share': ?share,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [LedgerRow].
  static const SchemanticType<LedgerRow> $schema = _LedgerRowTypeFactory();

  /// Group key: a date, category slug, account id or who.
  String get key {
    return _json['key'] as String;
  }

  /// Group key: a date, category slug, account id or who.
  set key(String value) {
    _json['key'] = value;
  }

  /// Display label.
  String get label {
    return _json['label'] as String;
  }

  /// Display label.
  set label(String value) {
    _json['label'] = value;
  }

  /// Sum (or average) for the group in base-currency minor units; null for
  /// `count`.
  int? get amountMinor {
    return (_json['amountMinor'] as num?)?.toInt();
  }

  /// Sum (or average) for the group in base-currency minor units; null for
  /// `count`.
  set amountMinor(int? value) {
    if (value == null) {
      _json.remove('amountMinor');
    } else {
      _json['amountMinor'] = value;
    }
  }

  /// Entries in the group.
  int get count {
    return (_json['count'] as num).toInt();
  }

  /// Entries in the group.
  set count(int value) {
    _json['count'] = value;
  }

  /// Share of the total, 0 to 1 (sum only).
  double? get share {
    return (_json['share'] as num?)?.toDouble();
  }

  /// Share of the total, 0 to 1 (sum only).
  set share(double? value) {
    if (value == null) {
      _json.remove('share');
    } else {
      _json['share'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [LedgerRow] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _LedgerRowTypeFactory extends SchemanticType<LedgerRow> {
  const _LedgerRowTypeFactory();

  @override
  LedgerRow parse(Object? json) {
    return LedgerRow._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'LedgerRow',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'One group.',
      'properties': <String, Object?>{
        'key': <String, Object?>{'type': 'string'},
        'label': <String, Object?>{'type': 'string'},
        'amountMinor': <String, Object?>{'type': 'integer'},
        'count': <String, Object?>{'type': 'integer'},
        'share': <String, Object?>{'type': 'number'},
      },
      'required': ['key', 'label', 'count'],
    },
    dependencies: [],
  );
}

/// `getBalances` input.
base class BalancesQuery {
  /// Creates a [BalancesQuery] from a JSON map.
  factory BalancesQuery.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  BalancesQuery._(this._json);

  BalancesQuery({String? scope}) {
    _json = {'scope': ?scope};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [BalancesQuery].
  static const SchemanticType<BalancesQuery> $schema =
      _BalancesQueryTypeFactory();

  /// Which accounts.
  String? get scope {
    return _json['scope'] as String?;
  }

  /// Which accounts.
  set scope(String? value) {
    if (value == null) {
      _json.remove('scope');
    } else {
      _json['scope'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [BalancesQuery] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _BalancesQueryTypeFactory extends SchemanticType<BalancesQuery> {
  const _BalancesQueryTypeFactory();

  @override
  BalancesQuery parse(Object? json) {
    return BalancesQuery._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'BalancesQuery',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Which accounts to include.',
      'properties': <String, Object?>{
        'scope': <String, Object?>{
          'type': 'string',
          'enum': ['all', 'mine', 'partner', 'joint'],
        },
      },
    },
    dependencies: [],
  );
}

/// `getBalances` output.
base class BalancesResult {
  /// Creates a [BalancesResult] from a JSON map.
  factory BalancesResult.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  BalancesResult._(this._json);

  BalancesResult({
    required String baseCurrency,
    required List<AccountBalance> accounts,
    int? totalBaseMinor,
    required bool partialView,
  }) {
    _json = {
      'baseCurrency': baseCurrency,
      'accounts': accounts.map((e) => e.toJson()).toList(),
      'totalBaseMinor': ?totalBaseMinor,
      'partialView': partialView,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [BalancesResult].
  static const SchemanticType<BalancesResult> $schema =
      _BalancesResultTypeFactory();

  /// The household base currency.
  String get baseCurrency {
    return _json['baseCurrency'] as String;
  }

  /// The household base currency.
  set baseCurrency(String value) {
    _json['baseCurrency'] = value;
  }

  /// The accounts.
  List<AccountBalance> get accounts {
    return (_json['accounts'] as List)
        .map((e) => AccountBalance.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The accounts.
  set accounts(List<AccountBalance> value) {
    _json['accounts'] = value.map((e) => e.toJson()).toList();
  }

  /// Sum in base currency; null when a rate is missing.
  int? get totalBaseMinor {
    return (_json['totalBaseMinor'] as num?)?.toInt();
  }

  /// Sum in base currency; null when a rate is missing.
  set totalBaseMinor(int? value) {
    if (value == null) {
      _json.remove('totalBaseMinor');
    } else {
      _json['totalBaseMinor'] = value;
    }
  }

  /// True when some household accounts are private to the partner.
  bool get partialView {
    return _json['partialView'] as bool;
  }

  /// True when some household accounts are private to the partner.
  set partialView(bool value) {
    _json['partialView'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [BalancesResult] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _BalancesResultTypeFactory extends SchemanticType<BalancesResult> {
  const _BalancesResultTypeFactory();

  @override
  BalancesResult parse(Object? json) {
    return BalancesResult._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'BalancesResult',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Account balances and the household total.',
      'properties': <String, Object?>{
        'baseCurrency': <String, Object?>{'type': 'string'},
        'accounts': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/AccountBalance'},
        },
        'totalBaseMinor': <String, Object?>{'type': 'integer'},
        'partialView': <String, Object?>{'type': 'boolean'},
      },
      'required': ['baseCurrency', 'accounts', 'partialView'],
    },
    dependencies: [AccountBalance.$schema],
  );
}

/// One account's balance.
base class AccountBalance {
  /// Creates a [AccountBalance] from a JSON map.
  factory AccountBalance.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  AccountBalance._(this._json);

  AccountBalance({
    required String accountId,
    required String name,
    required String currency,
    required int balanceMinor,
    required String scope,
  }) {
    _json = {
      'accountId': accountId,
      'name': name,
      'currency': currency,
      'balanceMinor': balanceMinor,
      'scope': scope,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [AccountBalance].
  static const SchemanticType<AccountBalance> $schema =
      _AccountBalanceTypeFactory();

  /// The account id.
  String get accountId {
    return _json['accountId'] as String;
  }

  /// The account id.
  set accountId(String value) {
    _json['accountId'] = value;
  }

  /// Display name.
  String get name {
    return _json['name'] as String;
  }

  /// Display name.
  set name(String value) {
    _json['name'] = value;
  }

  /// Account currency.
  String get currency {
    return _json['currency'] as String;
  }

  /// Account currency.
  set currency(String value) {
    _json['currency'] = value;
  }

  /// Balance in minor units of [currency].
  int get balanceMinor {
    return (_json['balanceMinor'] as num).toInt();
  }

  /// Balance in minor units of [currency].
  set balanceMinor(int value) {
    _json['balanceMinor'] = value;
  }

  /// `personal` or `joint`.
  String get scope {
    return _json['scope'] as String;
  }

  /// `personal` or `joint`.
  set scope(String value) {
    _json['scope'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [AccountBalance] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _AccountBalanceTypeFactory extends SchemanticType<AccountBalance> {
  const _AccountBalanceTypeFactory();

  @override
  AccountBalance parse(Object? json) {
    return AccountBalance._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'AccountBalance',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'One account.',
      'properties': <String, Object?>{
        'accountId': <String, Object?>{'type': 'string'},
        'name': <String, Object?>{'type': 'string'},
        'currency': <String, Object?>{'type': 'string'},
        'balanceMinor': <String, Object?>{'type': 'integer'},
        'scope': <String, Object?>{'type': 'string'},
      },
      'required': ['accountId', 'name', 'currency', 'balanceMinor', 'scope'],
    },
    dependencies: [],
  );
}

/// `getBudgets` input.
base class BudgetsQuery {
  /// Creates a [BudgetsQuery] from a JSON map.
  factory BudgetsQuery.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  BudgetsQuery._(this._json);

  BudgetsQuery({String? month}) {
    _json = {'month': ?month};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [BudgetsQuery].
  static const SchemanticType<BudgetsQuery> $schema =
      _BudgetsQueryTypeFactory();

  /// The month.
  String? get month {
    return _json['month'] as String?;
  }

  /// The month.
  set month(String? value) {
    if (value == null) {
      _json.remove('month');
    } else {
      _json['month'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [BudgetsQuery] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _BudgetsQueryTypeFactory extends SchemanticType<BudgetsQuery> {
  const _BudgetsQueryTypeFactory();

  @override
  BudgetsQuery parse(Object? json) {
    return BudgetsQuery._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'BudgetsQuery',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Budget month.',
      'properties': <String, Object?>{
        'month': <String, Object?>{
          'type': 'string',
          'description': 'YYYY-MM. Default: this month.',
        },
      },
    },
    dependencies: [],
  );
}

/// `getBudgets` output.
base class BudgetsResult {
  /// Creates a [BudgetsResult] from a JSON map.
  factory BudgetsResult.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  BudgetsResult._(this._json);

  BudgetsResult({
    required String month,
    required String currency,
    required List<BudgetStatus> budgets,
  }) {
    _json = {
      'month': month,
      'currency': currency,
      'budgets': budgets.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [BudgetsResult].
  static const SchemanticType<BudgetsResult> $schema =
      _BudgetsResultTypeFactory();

  /// The month.
  String get month {
    return _json['month'] as String;
  }

  /// The month.
  set month(String value) {
    _json['month'] = value;
  }

  /// Base currency of every figure.
  String get currency {
    return _json['currency'] as String;
  }

  /// Base currency of every figure.
  set currency(String value) {
    _json['currency'] = value;
  }

  /// The budgets.
  List<BudgetStatus> get budgets {
    return (_json['budgets'] as List)
        .map((e) => BudgetStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The budgets.
  set budgets(List<BudgetStatus> value) {
    _json['budgets'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [BudgetsResult] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _BudgetsResultTypeFactory extends SchemanticType<BudgetsResult> {
  const _BudgetsResultTypeFactory();

  @override
  BudgetsResult parse(Object? json) {
    return BudgetsResult._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'BudgetsResult',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Budgets with spent and remaining.',
      'properties': <String, Object?>{
        'month': <String, Object?>{'type': 'string'},
        'currency': <String, Object?>{'type': 'string'},
        'budgets': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/BudgetStatus'},
        },
      },
      'required': ['month', 'currency', 'budgets'],
    },
    dependencies: [BudgetStatus.$schema],
  );
}

/// One budget.
base class BudgetStatus {
  /// Creates a [BudgetStatus] from a JSON map.
  factory BudgetStatus.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  BudgetStatus._(this._json);

  BudgetStatus({
    required String budgetId,
    required String label,
    required int limitMinor,
    required int spentMinor,
    required int remainingMinor,
  }) {
    _json = {
      'budgetId': budgetId,
      'label': label,
      'limitMinor': limitMinor,
      'spentMinor': spentMinor,
      'remainingMinor': remainingMinor,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [BudgetStatus].
  static const SchemanticType<BudgetStatus> $schema =
      _BudgetStatusTypeFactory();

  /// The budget id.
  String get budgetId {
    return _json['budgetId'] as String;
  }

  /// The budget id.
  set budgetId(String value) {
    _json['budgetId'] = value;
  }

  /// Category name or "Total".
  String get label {
    return _json['label'] as String;
  }

  /// Category name or "Total".
  set label(String value) {
    _json['label'] = value;
  }

  /// Monthly limit.
  int get limitMinor {
    return (_json['limitMinor'] as num).toInt();
  }

  /// Monthly limit.
  set limitMinor(int value) {
    _json['limitMinor'] = value;
  }

  /// Spent this month.
  int get spentMinor {
    return (_json['spentMinor'] as num).toInt();
  }

  /// Spent this month.
  set spentMinor(int value) {
    _json['spentMinor'] = value;
  }

  /// Limit minus spent (negative when over).
  int get remainingMinor {
    return (_json['remainingMinor'] as num).toInt();
  }

  /// Limit minus spent (negative when over).
  set remainingMinor(int value) {
    _json['remainingMinor'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [BudgetStatus] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _BudgetStatusTypeFactory extends SchemanticType<BudgetStatus> {
  const _BudgetStatusTypeFactory();

  @override
  BudgetStatus parse(Object? json) {
    return BudgetStatus._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'BudgetStatus',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'One budget.',
      'properties': <String, Object?>{
        'budgetId': <String, Object?>{'type': 'string'},
        'label': <String, Object?>{'type': 'string'},
        'limitMinor': <String, Object?>{'type': 'integer'},
        'spentMinor': <String, Object?>{'type': 'integer'},
        'remainingMinor': <String, Object?>{'type': 'integer'},
      },
      'required': [
        'budgetId',
        'label',
        'limitMinor',
        'spentMinor',
        'remainingMinor',
      ],
    },
    dependencies: [],
  );
}

/// `findLoans` input.
base class LoansQuery {
  /// Creates a [LoansQuery] from a JSON map.
  factory LoansQuery.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  LoansQuery._(this._json);

  LoansQuery({String? person, String? status}) {
    _json = {'person': ?person, 'status': ?status};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [LoansQuery].
  static const SchemanticType<LoansQuery> $schema = _LoansQueryTypeFactory();

  /// A person's name.
  String? get person {
    return _json['person'] as String?;
  }

  /// A person's name.
  set person(String? value) {
    if (value == null) {
      _json.remove('person');
    } else {
      _json['person'] = value;
    }
  }

  /// `open`, `closed` or `all`; default open.
  String? get status {
    return _json['status'] as String?;
  }

  /// `open`, `closed` or `all`; default open.
  set status(String? value) {
    if (value == null) {
      _json.remove('status');
    } else {
      _json['status'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [LoansQuery] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _LoansQueryTypeFactory extends SchemanticType<LoansQuery> {
  const _LoansQueryTypeFactory();

  @override
  LoansQuery parse(Object? json) {
    return LoansQuery._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'LoansQuery',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Loan filters.',
      'properties': <String, Object?>{
        'person': <String, Object?>{'type': 'string'},
        'status': <String, Object?>{
          'type': 'string',
          'enum': ['open', 'closed', 'all'],
        },
      },
    },
    dependencies: [],
  );
}

/// `findLoans` output.
base class LoansResult {
  /// Creates a [LoansResult] from a JSON map.
  factory LoansResult.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  LoansResult._(this._json);

  LoansResult({required List<LoanInfo> loans}) {
    _json = {'loans': loans.map((e) => e.toJson()).toList()};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [LoansResult].
  static const SchemanticType<LoansResult> $schema = _LoansResultTypeFactory();

  /// The loans.
  List<LoanInfo> get loans {
    return (_json['loans'] as List)
        .map((e) => LoanInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The loans.
  set loans(List<LoanInfo> value) {
    _json['loans'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [LoansResult] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _LoansResultTypeFactory extends SchemanticType<LoansResult> {
  const _LoansResultTypeFactory();

  @override
  LoansResult parse(Object? json) {
    return LoansResult._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'LoansResult',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Loans and debts.',
      'properties': <String, Object?>{
        'loans': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/LoanInfo'},
        },
      },
      'required': ['loans'],
    },
    dependencies: [LoanInfo.$schema],
  );
}

/// One loan.
base class LoanInfo {
  /// Creates a [LoanInfo] from a JSON map.
  factory LoanInfo.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  LoanInfo._(this._json);

  LoanInfo({
    required String loanId,
    required String direction,
    required String personName,
    required int principalMinor,
    required int outstandingMinor,
    required String currency,
    required String status,
    String? dueOn,
  }) {
    _json = {
      'loanId': loanId,
      'direction': direction,
      'personName': personName,
      'principalMinor': principalMinor,
      'outstandingMinor': outstandingMinor,
      'currency': currency,
      'status': status,
      'dueOn': ?dueOn,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [LoanInfo].
  static const SchemanticType<LoanInfo> $schema = _LoanInfoTypeFactory();

  /// The loan id.
  String get loanId {
    return _json['loanId'] as String;
  }

  /// The loan id.
  set loanId(String value) {
    _json['loanId'] = value;
  }

  /// `given` (they owe us) or `taken` (we owe them).
  String get direction {
    return _json['direction'] as String;
  }

  /// `given` (they owe us) or `taken` (we owe them).
  set direction(String value) {
    _json['direction'] = value;
  }

  /// The other person.
  String get personName {
    return _json['personName'] as String;
  }

  /// The other person.
  set personName(String value) {
    _json['personName'] = value;
  }

  /// Amount lent or borrowed.
  int get principalMinor {
    return (_json['principalMinor'] as num).toInt();
  }

  /// Amount lent or borrowed.
  set principalMinor(int value) {
    _json['principalMinor'] = value;
  }

  /// Still owed.
  int get outstandingMinor {
    return (_json['outstandingMinor'] as num).toInt();
  }

  /// Still owed.
  set outstandingMinor(int value) {
    _json['outstandingMinor'] = value;
  }

  /// Currency.
  String get currency {
    return _json['currency'] as String;
  }

  /// Currency.
  set currency(String value) {
    _json['currency'] = value;
  }

  /// `open` or `closed`.
  String get status {
    return _json['status'] as String;
  }

  /// `open` or `closed`.
  set status(String value) {
    _json['status'] = value;
  }

  /// Due date.
  String? get dueOn {
    return _json['dueOn'] as String?;
  }

  /// Due date.
  set dueOn(String? value) {
    if (value == null) {
      _json.remove('dueOn');
    } else {
      _json['dueOn'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [LoanInfo] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _LoanInfoTypeFactory extends SchemanticType<LoanInfo> {
  const _LoanInfoTypeFactory();

  @override
  LoanInfo parse(Object? json) {
    return LoanInfo._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'LoanInfo',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'One loan or debt.',
      'properties': <String, Object?>{
        'loanId': <String, Object?>{'type': 'string'},
        'direction': <String, Object?>{'type': 'string'},
        'personName': <String, Object?>{'type': 'string'},
        'principalMinor': <String, Object?>{'type': 'integer'},
        'outstandingMinor': <String, Object?>{'type': 'integer'},
        'currency': <String, Object?>{'type': 'string'},
        'status': <String, Object?>{'type': 'string'},
        'dueOn': <String, Object?>{'type': 'string'},
      },
      'required': [
        'loanId',
        'direction',
        'personName',
        'principalMinor',
        'outstandingMinor',
        'currency',
        'status',
      ],
    },
    dependencies: [],
  );
}

/// `getFxRate` input.
base class FxRateQuery {
  /// Creates a [FxRateQuery] from a JSON map.
  factory FxRateQuery.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  FxRateQuery._(this._json);

  FxRateQuery({String? pair, String? date}) {
    _json = {'pair': ?pair, 'date': ?date};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [FxRateQuery].
  static const SchemanticType<FxRateQuery> $schema = _FxRateQueryTypeFactory();

  /// Pair in market convention.
  String? get pair {
    return _json['pair'] as String?;
  }

  /// Pair in market convention.
  set pair(String? value) {
    if (value == null) {
      _json.remove('pair');
    } else {
      _json['pair'] = value;
    }
  }

  /// The day.
  String? get date {
    return _json['date'] as String?;
  }

  /// The day.
  set date(String? value) {
    if (value == null) {
      _json.remove('date');
    } else {
      _json['date'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [FxRateQuery] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _FxRateQueryTypeFactory extends SchemanticType<FxRateQuery> {
  const _FxRateQueryTypeFactory();

  @override
  FxRateQuery parse(Object? json) {
    return FxRateQuery._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'FxRateQuery',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Rate lookup.',
      'properties': <String, Object?>{
        'pair': <String, Object?>{
          'type': 'string',
          'description': 'Pair, default "USD/IQD".',
        },
        'date': <String, Object?>{
          'type': 'string',
          'description': 'YYYY-MM-DD, default today.',
        },
      },
    },
    dependencies: [],
  );
}

/// `getFxRate` output.
base class FxRateResult {
  /// Creates a [FxRateResult] from a JSON map.
  factory FxRateResult.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  FxRateResult._(this._json);

  FxRateResult({
    required String pair,
    String? rate,
    String? source,
    String? asOf,
  }) {
    _json = {'pair': pair, 'rate': ?rate, 'source': ?source, 'asOf': ?asOf};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [FxRateResult].
  static const SchemanticType<FxRateResult> $schema =
      _FxRateResultTypeFactory();

  /// The pair.
  String get pair {
    return _json['pair'] as String;
  }

  /// The pair.
  set pair(String value) {
    _json['pair'] = value;
  }

  /// The rate as a decimal string, or null when none was entered.
  String? get rate {
    return _json['rate'] as String?;
  }

  /// The rate as a decimal string, or null when none was entered.
  set rate(String? value) {
    if (value == null) {
      _json.remove('rate');
    } else {
      _json['rate'] = value;
    }
  }

  /// `official` or `market`.
  String? get source {
    return _json['source'] as String?;
  }

  /// `official` or `market`.
  set source(String? value) {
    if (value == null) {
      _json.remove('source');
    } else {
      _json['source'] = value;
    }
  }

  /// The day the rate was entered for.
  String? get asOf {
    return _json['asOf'] as String?;
  }

  /// The day the rate was entered for.
  set asOf(String? value) {
    if (value == null) {
      _json.remove('asOf');
    } else {
      _json['asOf'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [FxRateResult] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _FxRateResultTypeFactory extends SchemanticType<FxRateResult> {
  const _FxRateResultTypeFactory();

  @override
  FxRateResult parse(Object? json) {
    return FxRateResult._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'FxRateResult',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'The household rate for a day.',
      'properties': <String, Object?>{
        'pair': <String, Object?>{'type': 'string'},
        'rate': <String, Object?>{'type': 'string'},
        'source': <String, Object?>{'type': 'string'},
        'asOf': <String, Object?>{'type': 'string'},
      },
      'required': ['pair'],
    },
    dependencies: [],
  );
}

/// `findEntries` input.
base class FindEntriesQuery {
  /// Creates a [FindEntriesQuery] from a JSON map.
  factory FindEntriesQuery.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  FindEntriesQuery._(this._json);

  FindEntriesQuery({String? text, String? from, String? to, String? amount}) {
    _json = {'text': ?text, 'from': ?from, 'to': ?to, 'amount': ?amount};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [FindEntriesQuery].
  static const SchemanticType<FindEntriesQuery> $schema =
      _FindEntriesQueryTypeFactory();

  /// Words in title or note.
  String? get text {
    return _json['text'] as String?;
  }

  /// Words in title or note.
  set text(String? value) {
    if (value == null) {
      _json.remove('text');
    } else {
      _json['text'] = value;
    }
  }

  /// First day.
  String? get from {
    return _json['from'] as String?;
  }

  /// First day.
  set from(String? value) {
    if (value == null) {
      _json.remove('from');
    } else {
      _json['from'] = value;
    }
  }

  /// Last day.
  String? get to {
    return _json['to'] as String?;
  }

  /// Last day.
  set to(String? value) {
    if (value == null) {
      _json.remove('to');
    } else {
      _json['to'] = value;
    }
  }

  /// Amount as written, major units.
  String? get amount {
    return _json['amount'] as String?;
  }

  /// Amount as written, major units.
  set amount(String? value) {
    if (value == null) {
      _json.remove('amount');
    } else {
      _json['amount'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [FindEntriesQuery] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _FindEntriesQueryTypeFactory
    extends SchemanticType<FindEntriesQuery> {
  const _FindEntriesQueryTypeFactory();

  @override
  FindEntriesQuery parse(Object? json) {
    return FindEntriesQuery._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'FindEntriesQuery',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Find saved entries.',
      'properties': <String, Object?>{
        'text': <String, Object?>{'type': 'string'},
        'from': <String, Object?>{
          'type': 'string',
          'description': 'YYYY-MM-DD. Default: 60 days ago.',
        },
        'to': <String, Object?>{
          'type': 'string',
          'description': 'YYYY-MM-DD. Default: today.',
        },
        'amount': <String, Object?>{
          'type': 'string',
          'description': 'Amount as written, e.g. "45.20".',
        },
      },
    },
    dependencies: [],
  );
}

/// `findEntries` output, shaped for `TransactionList`.
base class FoundEntries {
  /// Creates a [FoundEntries] from a JSON map.
  factory FoundEntries.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  FoundEntries._(this._json);

  FoundEntries({required List<FoundEntry> items}) {
    _json = {'items': items.map((e) => e.toJson()).toList()};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [FoundEntries].
  static const SchemanticType<FoundEntries> $schema =
      _FoundEntriesTypeFactory();

  /// The entries.
  List<FoundEntry> get items {
    return (_json['items'] as List)
        .map((e) => FoundEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The entries.
  set items(List<FoundEntry> value) {
    _json['items'] = value.map((e) => e.toJson()).toList();
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [FoundEntries] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _FoundEntriesTypeFactory extends SchemanticType<FoundEntries> {
  const _FoundEntriesTypeFactory();

  @override
  FoundEntries parse(Object? json) {
    return FoundEntries._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'FoundEntries',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Matching entries, newest first, at most 10.',
      'properties': <String, Object?>{
        'items': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/FoundEntry'},
        },
      },
      'required': ['items'],
    },
    dependencies: [FoundEntry.$schema],
  );
}

/// One entry, in the `TransactionList` item shape.
base class FoundEntry {
  /// Creates a [FoundEntry] from a JSON map.
  factory FoundEntry.fromJson(Map<String, dynamic> json) => $schema.parse(json);

  FoundEntry._(this._json);

  FoundEntry({
    required String txnId,
    required String title,
    required String subtitle,
    required int amountMinor,
    required String currency,
    required String type,
    required String occurredOn,
  }) {
    _json = {
      'txnId': txnId,
      'title': title,
      'subtitle': subtitle,
      'amountMinor': amountMinor,
      'currency': currency,
      'type': type,
      'occurredOn': occurredOn,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [FoundEntry].
  static const SchemanticType<FoundEntry> $schema = _FoundEntryTypeFactory();

  /// The transaction id.
  String get txnId {
    return _json['txnId'] as String;
  }

  /// The transaction id.
  set txnId(String value) {
    _json['txnId'] = value;
  }

  /// Title.
  String get title {
    return _json['title'] as String;
  }

  /// Title.
  set title(String value) {
    _json['title'] = value;
  }

  /// Category and account.
  String get subtitle {
    return _json['subtitle'] as String;
  }

  /// Category and account.
  set subtitle(String value) {
    _json['subtitle'] = value;
  }

  /// Amount in minor units of [currency].
  int get amountMinor {
    return (_json['amountMinor'] as num).toInt();
  }

  /// Amount in minor units of [currency].
  set amountMinor(int value) {
    _json['amountMinor'] = value;
  }

  /// Currency.
  String get currency {
    return _json['currency'] as String;
  }

  /// Currency.
  set currency(String value) {
    _json['currency'] = value;
  }

  /// Ledger type.
  String get type {
    return _json['type'] as String;
  }

  /// Ledger type.
  set type(String value) {
    _json['type'] = value;
  }

  /// Date.
  String get occurredOn {
    return _json['occurredOn'] as String;
  }

  /// Date.
  set occurredOn(String value) {
    _json['occurredOn'] = value;
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [FoundEntry] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _FoundEntryTypeFactory extends SchemanticType<FoundEntry> {
  const _FoundEntryTypeFactory();

  @override
  FoundEntry parse(Object? json) {
    return FoundEntry._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'FoundEntry',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'One saved entry.',
      'properties': <String, Object?>{
        'txnId': <String, Object?>{'type': 'string'},
        'title': <String, Object?>{'type': 'string'},
        'subtitle': <String, Object?>{'type': 'string'},
        'amountMinor': <String, Object?>{'type': 'integer'},
        'currency': <String, Object?>{'type': 'string'},
        'type': <String, Object?>{'type': 'string'},
        'occurredOn': <String, Object?>{'type': 'string'},
      },
      'required': [
        'txnId',
        'title',
        'subtitle',
        'amountMinor',
        'currency',
        'type',
        'occurredOn',
      ],
    },
    dependencies: [],
  );
}
