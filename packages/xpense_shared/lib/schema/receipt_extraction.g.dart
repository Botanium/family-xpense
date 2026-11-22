// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipt_extraction.dart';

// **************************************************************************
// SchemaGenerator
// **************************************************************************

/// Structured output of `receipt_lines.prompt` (AI_PIPELINE 8):
/// merchant, date, currency, total and line items.
base class ReceiptExtraction {
  /// Creates a [ReceiptExtraction] from a JSON map.
  factory ReceiptExtraction.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  ReceiptExtraction._(this._json);

  ReceiptExtraction({
    String? merchant,
    String? date,
    String? currency,
    int? totalMinor,
    List<ReceiptLine>? lines,
  }) {
    _json = {
      'merchant': ?merchant,
      'date': ?date,
      'currency': ?currency,
      'totalMinor': ?totalMinor,
      'lines': ?lines?.map((e) => e.toJson()).toList(),
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [ReceiptExtraction].
  static const SchemanticType<ReceiptExtraction> $schema =
      _ReceiptExtractionTypeFactory();

  /// The merchant name as printed.
  String? get merchant {
    return _json['merchant'] as String?;
  }

  /// The merchant name as printed.
  set merchant(String? value) {
    if (value == null) {
      _json.remove('merchant');
    } else {
      _json['merchant'] = value;
    }
  }

  /// The receipt date, `YYYY-MM-DD`.
  String? get date {
    return _json['date'] as String?;
  }

  /// The receipt date, `YYYY-MM-DD`.
  set date(String? value) {
    if (value == null) {
      _json.remove('date');
    } else {
      _json['date'] = value;
    }
  }

  /// ISO currency code of the amounts.
  String? get currency {
    return _json['currency'] as String?;
  }

  /// ISO currency code of the amounts.
  set currency(String? value) {
    if (value == null) {
      _json.remove('currency');
    } else {
      _json['currency'] = value;
    }
  }

  /// The printed total in minor units of [currency].
  int? get totalMinor {
    return (_json['totalMinor'] as num?)?.toInt();
  }

  /// The printed total in minor units of [currency].
  set totalMinor(int? value) {
    if (value == null) {
      _json.remove('totalMinor');
    } else {
      _json['totalMinor'] = value;
    }
  }

  /// The line items, in printed order.
  List<ReceiptLine>? get lines {
    return (_json['lines'] as List?)
        ?.map((e) => ReceiptLine.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// The line items, in printed order.
  set lines(List<ReceiptLine>? value) {
    if (value == null) {
      _json.remove('lines');
    } else {
      _json['lines'] = value.map((e) => e.toJson()).toList();
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [ReceiptExtraction] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _ReceiptExtractionTypeFactory
    extends SchemanticType<ReceiptExtraction> {
  const _ReceiptExtractionTypeFactory();

  @override
  ReceiptExtraction parse(Object? json) {
    return ReceiptExtraction._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'ReceiptExtraction',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'Merchant, date, total and line items of a receipt.',
      'properties': <String, Object?>{
        'merchant': <String, Object?>{'type': 'string'},
        'date': <String, Object?>{
          'type': 'string',
          'description': 'Receipt date, YYYY-MM-DD.',
        },
        'currency': <String, Object?>{
          'type': 'string',
          'enum': ['USD', 'IQD'],
        },
        'totalMinor': <String, Object?>{
          'type': 'integer',
          'description': 'Total in minor units of currency.',
          'minimum': 0,
        },
        'lines': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{r'$ref': r'#/$defs/ReceiptLine'},
        },
      },
    },
    dependencies: [ReceiptLine.$schema],
  );
}

/// One line item of a receipt.
base class ReceiptLine {
  /// Creates a [ReceiptLine] from a JSON map.
  factory ReceiptLine.fromJson(Map<String, dynamic> json) =>
      $schema.parse(json);

  ReceiptLine._(this._json);

  ReceiptLine({
    required String text,
    required int amountMinor,
    String? categoryId,
  }) {
    _json = {
      'text': text,
      'amountMinor': amountMinor,
      'categoryId': ?categoryId,
    };
  }

  late final Map<String, dynamic> _json;

  /// The JSON schema and type descriptor for [ReceiptLine].
  static const SchemanticType<ReceiptLine> $schema = _ReceiptLineTypeFactory();

  /// The line text as printed.
  String get text {
    return _json['text'] as String;
  }

  /// The line text as printed.
  set text(String value) {
    _json['text'] = value;
  }

  /// The line amount in minor units of the receipt currency.
  int get amountMinor {
    return (_json['amountMinor'] as num).toInt();
  }

  /// The line amount in minor units of the receipt currency.
  set amountMinor(int value) {
    _json['amountMinor'] = value;
  }

  /// A suggested category slug or id.
  String? get categoryId {
    return _json['categoryId'] as String?;
  }

  /// A suggested category slug or id.
  set categoryId(String? value) {
    if (value == null) {
      _json.remove('categoryId');
    } else {
      _json['categoryId'] = value;
    }
  }

  @override
  String toString() {
    return _json.toString();
  }

  /// Serializes this [ReceiptLine] to a JSON map.
  Map<String, dynamic> toJson() {
    return _json;
  }
}

base class _ReceiptLineTypeFactory extends SchemanticType<ReceiptLine> {
  const _ReceiptLineTypeFactory();

  @override
  ReceiptLine parse(Object? json) {
    return ReceiptLine._(json as Map<String, dynamic>);
  }

  @override
  JsonSchemaMetadata get schemaMetadata => JsonSchemaMetadata(
    name: 'ReceiptLine',
    definition: <String, Object?>{
      'type': 'object',
      'description': 'One line item of a receipt.',
      'properties': <String, Object?>{
        'text': <String, Object?>{'type': 'string'},
        'amountMinor': <String, Object?>{
          'type': 'integer',
          'description': 'Line amount in minor units of currency.',
        },
        'categoryId': <String, Object?>{'type': 'string'},
      },
      'required': ['text', 'amountMinor'],
    },
    dependencies: [],
  );
}
