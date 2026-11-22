// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'decide.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

/// The phone's request to `POST /decide` (AI_PIPELINE 7):
/// `{text, lang, parsed, hints, ask, candidates?}`.
///
/// The server builds the question options from the household's own data,
/// so the phone sends only keys, never option lists.
base class DecideRequest {
  /// Creates a [DecideRequest] from a JSON map.
  factory DecideRequest.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  DecideRequest._(this._json);

  DecideRequest({
    required String text,
    required String lang,
    DecideParsed? parsed,
    List<ParseHint>? hints,
    required List<String> ask,
    List<DuplicateCandidate>? candidates,
  }) {
    _json = {
      'text': text,
      'lang': lang,
      'parsed': ?parsed?.toJson(),
      'hints': ?hints?.map((e) => e.toJson()).toList(),
      'ask': ask,
      'candidates': ?candidates?.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [DecideRequest].
  static const SchemanticType<DecideRequest> $schema =
      _DecideRequestTypeFactory();

  /// The message text.
  String get text {
    return _json['text'] as String;
  }

  /// The message text.
  set text(String value) {
    _json['text'] = value;
  }

  /// Language code of [text]; `en` only for now (D-36).
  String get lang {
    return _json['lang'] as String;
  }

  /// Language code of [text]; `en` only for now (D-36).
  set lang(String value) {
    _json['lang'] = value;
  }

  /// What the fast parser already settled.
  DecideParsed? get parsed {
    return _json['parsed'] == null
        ? null
        : DecideParsed.fromJson(_json['parsed'] as Map<String, dynamic>);
  }

  /// What the fast parser already settled.
  set parsed(DecideParsed? value) {
    if (value == null) {
      _json.remove('parsed');
    } else {
      _json['parsed'] = value.toJson();
    }
  }

  /// Hints from the fast parser.
  List<ParseHint>? get hints {
    return (_json['hints'] as List?)
        ?.map((e) => ParseHint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Hints from the fast parser.
  set hints(List<ParseHint>? value) {
    if (value == null) {
      _json.remove('hints');
    } else {
      _json['hints'] = value.map((e) => e.toJson()).toList();
    }
  }

  /// The question keys to ask, from `decideQuestionKeys`.
  List<String> get ask {
    return (_json['ask'] as List).cast<String>();
  }

  /// The question keys to ask, from `decideQuestionKeys`.
  set ask(List<String> value) {
    _json['ask'] = value;
  }

  /// Deterministic duplicate candidates (same account and amount, date
  /// within one day). The `duplicate` question is asked only with these.
  List<DuplicateCandidate>? get candidates {
    return (_json['candidates'] as List?)
        ?.map((e) => DuplicateCandidate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Deterministic duplicate candidates (same account and amount, date
  /// within one day). The `duplicate` question is asked only with these.
  set candidates(List<DuplicateCandidate>? value) {
    if (value == null) {
      _json.remove('candidates');
    } else {
      _json['candidates'] = value.map((e) => e.toJson()).toList();
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [DecideRequest] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _DecideRequestTypeFactory extends SchemanticType<DecideRequest> {
  const _DecideRequestTypeFactory();

  @override
  DecideRequest parse(Object? json) {
    return DecideRequest._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'DecideRequest',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Request to the Decisions proxy.',
      'properties': <String, Object?>{
        'text': <String, Object?>{'type': 'string'},
        'lang': <String, Object?>{'type': 'string'},
        'parsed': <String, Object?>{r'$ref': r'#/$defs/DecideParsed'},
        'hints': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/ParseHint'},
        },
        'ask': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
        'candidates': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/DuplicateCandidate'},
        },
      },
      'required': ['text', 'lang', 'ask'],
    },
    dependencies: [
      DecideParsed.$schema,
      ParseHint.$schema,
      DuplicateCandidate.$schema,
    ],
  );
}

/// The settled part of a message sent with a decide request.
base class DecideParsed {
  /// Creates a [DecideParsed] from a JSON map.
  factory DecideParsed.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  DecideParsed._(this._json);

  DecideParsed({int? amountMinor, String? currency, String? date}) {
    _json = {'amountMinor': ?amountMinor, 'currency': ?currency, 'date': ?date};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [DecideParsed].
  static const SchemanticType<DecideParsed> $schema =
      _DecideParsedTypeFactory();

  /// Amount in minor units of [currency].
  int? get amountMinor {
    return (_json['amountMinor'] as num?)?.toInt();
  }

  /// Amount in minor units of [currency].
  set amountMinor(int? value) {
    if (value == null) {
      _json.remove('amountMinor');
    } else {
      _json['amountMinor'] = value;
    }
  }

  /// ISO currency code.
  String? get currency {
    return _json['currency'] as String?;
  }

  /// ISO currency code.
  set currency(String? value) {
    if (value == null) {
      _json.remove('currency');
    } else {
      _json['currency'] = value;
    }
  }

  /// Household-local date, `YYYY-MM-DD`.
  String? get date {
    return _json['date'] as String?;
  }

  /// Household-local date, `YYYY-MM-DD`.
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

  /// Serializes this [DecideParsed] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _DecideParsedTypeFactory extends SchemanticType<DecideParsed> {
  const _DecideParsedTypeFactory();

  @override
  DecideParsed parse(Object? json) {
    return DecideParsed._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'DecideParsed',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Amount, currency and date already parsed.',
      'properties': <String, Object?>{
        'amountMinor': <String, Object?>{'type': 'integer', 'minimum': 0},
        'currency': <String, Object?>{
          'type': 'string',
          'enum': ['USD', 'IQD'],
        },
        'date': <String, Object?>{'type': 'string'},
      },
    },
    dependencies: [],
  );
}

/// A recent entry that may be the same event as the message.
base class DuplicateCandidate {
  /// Creates a [DuplicateCandidate] from a JSON map.
  factory DuplicateCandidate.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  DuplicateCandidate._(this._json);

  DuplicateCandidate({
    required String txnId,
    int? amountMinor,
    String? currency,
    String? occurredOn,
    String? title,
  }) {
    _json = {
      'txnId': txnId,
      'amountMinor': ?amountMinor,
      'currency': ?currency,
      'occurredOn': ?occurredOn,
      'title': ?title,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [DuplicateCandidate].
  static const SchemanticType<DuplicateCandidate> $schema =
      _DuplicateCandidateTypeFactory();

  /// The saved transaction's id; also the option key.
  String get txnId {
    return _json['txnId'] as String;
  }

  /// The saved transaction's id; also the option key.
  set txnId(String value) {
    _json['txnId'] = value;
  }

  /// Amount in minor units of [currency].
  int? get amountMinor {
    return (_json['amountMinor'] as num?)?.toInt();
  }

  /// Amount in minor units of [currency].
  set amountMinor(int? value) {
    if (value == null) {
      _json.remove('amountMinor');
    } else {
      _json['amountMinor'] = value;
    }
  }

  /// ISO currency code.
  String? get currency {
    return _json['currency'] as String?;
  }

  /// ISO currency code.
  set currency(String? value) {
    if (value == null) {
      _json.remove('currency');
    } else {
      _json['currency'] = value;
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

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [DuplicateCandidate] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _DuplicateCandidateTypeFactory
    extends SchemanticType<DuplicateCandidate> {
  const _DuplicateCandidateTypeFactory();

  @override
  DuplicateCandidate parse(Object? json) {
    return DuplicateCandidate._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'DuplicateCandidate',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'A recent saved entry that may be a duplicate.',
      'properties': <String, Object?>{
        'txnId': <String, Object?>{'type': 'string'},
        'amountMinor': <String, Object?>{'type': 'integer'},
        'currency': <String, Object?>{
          'type': 'string',
          'enum': ['USD', 'IQD'],
        },
        'occurredOn': <String, Object?>{'type': 'string'},
        'title': <String, Object?>{'type': 'string'},
      },
      'required': ['txnId'],
    },
    dependencies: [],
  );
}

/// The proxy's answer (AI_PIPELINE 7). Each field answers the question key
/// of the same name; unasked questions are absent.
base class DecideResponse {
  /// Creates a [DecideResponse] from a JSON map.
  factory DecideResponse.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  DecideResponse._(this._json);

  DecideResponse({
    ChoiceAnswer? intent,
    ChoiceAnswer? category,
    ChoiceAnswer? account,
    ChoiceAnswer? toAccount,
    ChoiceAnswer? person,
    ChoiceAnswer? who,
    YesNoAnswer? multiEntry,
    YesNoAnswer? repayable,
    YesNoAnswer? needsFollowup,
    YesNoAnswer? isRecurring,
    YesNoAnswer? duplicate,
    bool? calibrated,
    bool? unavailable,
  }) {
    _json = {
      'intent': ?intent?.toJson(),
      'category': ?category?.toJson(),
      'account': ?account?.toJson(),
      'to_account': ?toAccount?.toJson(),
      'person': ?person?.toJson(),
      'who': ?who?.toJson(),
      'multi_entry': ?multiEntry?.toJson(),
      'repayable': ?repayable?.toJson(),
      'needs_followup': ?needsFollowup?.toJson(),
      'is_recurring': ?isRecurring?.toJson(),
      'duplicate': ?duplicate?.toJson(),
      'calibrated': ?calibrated,
      'unavailable': ?unavailable,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [DecideResponse].
  static const SchemanticType<DecideResponse> $schema =
      _DecideResponseTypeFactory();

  /// Answer to `intent`.
  ChoiceAnswer? get intent {
    return _json['intent'] == null
        ? null
        : ChoiceAnswer.fromJson(_json['intent'] as Map<String, dynamic>);
  }

  /// Answer to `intent`.
  set intent(ChoiceAnswer? value) {
    if (value == null) {
      _json.remove('intent');
    } else {
      _json['intent'] = value.toJson();
    }
  }

  /// Answer to `category`.
  ChoiceAnswer? get category {
    return _json['category'] == null
        ? null
        : ChoiceAnswer.fromJson(_json['category'] as Map<String, dynamic>);
  }

  /// Answer to `category`.
  set category(ChoiceAnswer? value) {
    if (value == null) {
      _json.remove('category');
    } else {
      _json['category'] = value.toJson();
    }
  }

  /// Answer to `account`: the account the money left from or arrived in.
  ChoiceAnswer? get account {
    return _json['account'] == null
        ? null
        : ChoiceAnswer.fromJson(_json['account'] as Map<String, dynamic>);
  }

  /// Answer to `account`: the account the money left from or arrived in.
  set account(ChoiceAnswer? value) {
    if (value == null) {
      _json.remove('account');
    } else {
      _json['account'] = value.toJson();
    }
  }

  /// Answer to `to_account`: the destination account of a transfer or
  /// savings move (WP-S4).
  ChoiceAnswer? get toAccount {
    return _json['to_account'] == null
        ? null
        : ChoiceAnswer.fromJson(_json['to_account'] as Map<String, dynamic>);
  }

  /// Answer to `to_account`: the destination account of a transfer or
  /// savings move (WP-S4).
  set toAccount(ChoiceAnswer? value) {
    if (value == null) {
      _json.remove('to_account');
    } else {
      _json['to_account'] = value.toJson();
    }
  }

  /// Answer to `person`: the household's person a loan, repayment or gift
  /// is with (WP-S4).
  ChoiceAnswer? get person {
    return _json['person'] == null
        ? null
        : ChoiceAnswer.fromJson(_json['person'] as Map<String, dynamic>);
  }

  /// Answer to `person`: the household's person a loan, repayment or gift
  /// is with (WP-S4).
  set person(ChoiceAnswer? value) {
    if (value == null) {
      _json.remove('person');
    } else {
      _json['person'] = value.toJson();
    }
  }

  /// Answer to `who`.
  ChoiceAnswer? get who {
    return _json['who'] == null
        ? null
        : ChoiceAnswer.fromJson(_json['who'] as Map<String, dynamic>);
  }

  /// Answer to `who`.
  set who(ChoiceAnswer? value) {
    if (value == null) {
      _json.remove('who');
    } else {
      _json['who'] = value.toJson();
    }
  }

  /// Answer to `multi_entry`; at 0.5 or above the phone re-routes to the
  /// agent.
  YesNoAnswer? get multiEntry {
    return _json['multi_entry'] == null
        ? null
        : YesNoAnswer.fromJson(_json['multi_entry'] as Map<String, dynamic>);
  }

  /// Answer to `multi_entry`; at 0.5 or above the phone re-routes to the
  /// agent.
  set multiEntry(YesNoAnswer? value) {
    if (value == null) {
      _json.remove('multi_entry');
    } else {
      _json['multi_entry'] = value.toJson();
    }
  }

  /// Answer to `repayable`.
  YesNoAnswer? get repayable {
    return _json['repayable'] == null
        ? null
        : YesNoAnswer.fromJson(_json['repayable'] as Map<String, dynamic>);
  }

  /// Answer to `repayable`.
  set repayable(YesNoAnswer? value) {
    if (value == null) {
      _json.remove('repayable');
    } else {
      _json['repayable'] = value.toJson();
    }
  }

  /// Answer to `needs_followup`.
  YesNoAnswer? get needsFollowup {
    return _json['needs_followup'] == null
        ? null
        : YesNoAnswer.fromJson(_json['needs_followup'] as Map<String, dynamic>);
  }

  /// Answer to `needs_followup`.
  set needsFollowup(YesNoAnswer? value) {
    if (value == null) {
      _json.remove('needs_followup');
    } else {
      _json['needs_followup'] = value.toJson();
    }
  }

  /// Answer to `is_recurring`.
  YesNoAnswer? get isRecurring {
    return _json['is_recurring'] == null
        ? null
        : YesNoAnswer.fromJson(_json['is_recurring'] as Map<String, dynamic>);
  }

  /// Answer to `is_recurring`.
  set isRecurring(YesNoAnswer? value) {
    if (value == null) {
      _json.remove('is_recurring');
    } else {
      _json['is_recurring'] = value.toJson();
    }
  }

  /// Answer to `duplicate`: whether the message is one of the candidates.
  YesNoAnswer? get duplicate {
    return _json['duplicate'] == null
        ? null
        : YesNoAnswer.fromJson(_json['duplicate'] as Map<String, dynamic>);
  }

  /// Answer to `duplicate`: whether the message is one of the candidates.
  set duplicate(YesNoAnswer? value) {
    if (value == null) {
      _json.remove('duplicate');
    } else {
      _json['duplicate'] = value.toJson();
    }
  }

  /// `false` when the answers came from the Flash-Lite fallback; the phone
  /// then caps confidences at `conf_on_device_cap`.
  bool? get calibrated {
    return _json['calibrated'] as bool?;
  }

  /// `false` when the answers came from the Flash-Lite fallback; the phone
  /// then caps confidences at `conf_on_device_cap`.
  set calibrated(bool? value) {
    if (value == null) {
      _json.remove('calibrated');
    } else {
      _json['calibrated'] = value;
    }
  }

  /// `true` when no classifier was available; the phone falls back to
  /// on-device classification or local pickers.
  bool? get unavailable {
    return _json['unavailable'] as bool?;
  }

  /// `true` when no classifier was available; the phone falls back to
  /// on-device classification or local pickers.
  set unavailable(bool? value) {
    if (value == null) {
      _json.remove('unavailable');
    } else {
      _json['unavailable'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [DecideResponse] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _DecideResponseTypeFactory extends SchemanticType<DecideResponse> {
  const _DecideResponseTypeFactory();

  @override
  DecideResponse parse(Object? json) {
    return DecideResponse._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'DecideResponse',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Answers from the Decisions proxy.',
      'properties': <String, Object?>{
        'intent': <String, Object?>{r'$ref': r'#/$defs/ChoiceAnswer'},
        'category': <String, Object?>{r'$ref': r'#/$defs/ChoiceAnswer'},
        'account': <String, Object?>{r'$ref': r'#/$defs/ChoiceAnswer'},
        'to_account': <String, Object?>{r'$ref': r'#/$defs/ChoiceAnswer'},
        'person': <String, Object?>{r'$ref': r'#/$defs/ChoiceAnswer'},
        'who': <String, Object?>{r'$ref': r'#/$defs/ChoiceAnswer'},
        'multi_entry': <String, Object?>{r'$ref': r'#/$defs/YesNoAnswer'},
        'repayable': <String, Object?>{r'$ref': r'#/$defs/YesNoAnswer'},
        'needs_followup': <String, Object?>{r'$ref': r'#/$defs/YesNoAnswer'},
        'is_recurring': <String, Object?>{r'$ref': r'#/$defs/YesNoAnswer'},
        'duplicate': <String, Object?>{r'$ref': r'#/$defs/YesNoAnswer'},
        'calibrated': <String, Object?>{'type': 'boolean'},
        'unavailable': <String, Object?>{'type': 'boolean'},
      },
    },
    dependencies: [ChoiceAnswer.$schema, YesNoAnswer.$schema],
  );
}

/// The answer to a `choice` question.
base class ChoiceAnswer {
  /// Creates a [ChoiceAnswer] from a JSON map.
  factory ChoiceAnswer.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  ChoiceAnswer._(this._json);

  ChoiceAnswer({
    String? choice,
    Map<String, num>? probabilities,
    double? confidence,
  }) {
    _json = {
      'choice': ?choice,
      'probabilities': ?probabilities,
      'confidence': ?confidence,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [ChoiceAnswer].
  static const SchemanticType<ChoiceAnswer> $schema =
      _ChoiceAnswerTypeFactory();

  /// The most probable option key.
  String? get choice {
    return _json['choice'] as String?;
  }

  /// The most probable option key.
  set choice(String? value) {
    if (value == null) {
      _json.remove('choice');
    } else {
      _json['choice'] = value;
    }
  }

  /// Probability per option key. `num` so that a probability of exactly 0
  /// or 1 encoded as a JSON integer still reads.
  Map<String, num>? get probabilities {
    return (_json['probabilities'] as Map?)?.cast<String, num>();
  }

  /// Probability per option key. `num` so that a probability of exactly 0
  /// or 1 encoded as a JSON integer still reads.
  set probabilities(Map<String, num>? value) {
    if (value == null) {
      _json.remove('probabilities');
    } else {
      _json['probabilities'] = value;
    }
  }

  /// The classifier's confidence in [choice], 0 to 1.
  double? get confidence {
    return (_json['confidence'] as num?)?.toDouble();
  }

  /// The classifier's confidence in [choice], 0 to 1.
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

  /// Serializes this [ChoiceAnswer] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _ChoiceAnswerTypeFactory extends SchemanticType<ChoiceAnswer> {
  const _ChoiceAnswerTypeFactory();

  @override
  ChoiceAnswer parse(Object? json) {
    return ChoiceAnswer._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'ChoiceAnswer',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Answer to a choice question.',
      'properties': <String, Object?>{
        'choice': <String, Object?>{'type': 'string'},
        'probabilities': <String, Object?>{
          'type': 'object',
          'additionalProperties': <String, Object?>{'type': 'number'},
        },
        'confidence': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
      },
    },
    dependencies: [],
  );
}

/// The answer to a yes/no (`noul`) question.
base class YesNoAnswer {
  /// Creates a [YesNoAnswer] from a JSON map.
  factory YesNoAnswer.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  YesNoAnswer._(this._json);

  YesNoAnswer({double? probability, double? confidence}) {
    _json = {'probability': ?probability, 'confidence': ?confidence};
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [YesNoAnswer].
  static const SchemanticType<YesNoAnswer> $schema = _YesNoAnswerTypeFactory();

  /// Probability of yes, 0 to 1.
  double? get probability {
    return (_json['probability'] as num?)?.toDouble();
  }

  /// Probability of yes, 0 to 1.
  set probability(double? value) {
    if (value == null) {
      _json.remove('probability');
    } else {
      _json['probability'] = value;
    }
  }

  /// The classifier's confidence, 0 to 1.
  double? get confidence {
    return (_json['confidence'] as num?)?.toDouble();
  }

  /// The classifier's confidence, 0 to 1.
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

  /// Serializes this [YesNoAnswer] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _YesNoAnswerTypeFactory extends SchemanticType<YesNoAnswer> {
  const _YesNoAnswerTypeFactory();

  @override
  YesNoAnswer parse(Object? json) {
    return YesNoAnswer._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'YesNoAnswer',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Answer to a yes/no question.',
      'properties': <String, Object?>{
        'probability': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
        'confidence': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
      },
    },
    dependencies: [],
  );
}
