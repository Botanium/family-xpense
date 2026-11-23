/// The checks `outputGuard` applies to every surface the agent emits
/// (AI_PIPELINE 10, "Model invents an amount").
///
/// A draft whose id the latest `prepareEntries` returned is replaced by the
/// tool's exact draft. Any other draft is kept only when it parses as an
/// `EntryDraft` and its amount is backed by something the model did not
/// make up:
/// - the same draft (id, amount, currency) in the latest `prepareEntries`
///   result of this model call, or
/// - a figure the fast parser finds in the user's own messages, or
/// - a minor-unit figure in another tool's result (for example an entry
///   `findEntries` returned).
///
/// Everything here works on the JSON form of Genkit parts, so it is pure and
/// unit-tested without a model.
library;

import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The MIME type of A2UI data parts.
const a2uiMime = 'application/a2ui+json';

/// The metadata key holding a part's original Express source.
const a2uiExpressKey = 'a2uiExpress';

/// The tool whose drafts are authoritative.
const prepareEntriesTool = 'prepareEntries';

/// What backs the amounts of one model call. Built once per model call;
/// its fields are never changed after construction.
final class GuardFacts {
  /// Creates the facts.
  const new({
    this.preparedDrafts = const {},
    this.messageValues = const {},
    this.toolMinorAmounts = const {},
  });

  /// Reads the facts from a model request's messages (JSON form).
  factory fromMessages(List<Map<String, dynamic>> messages) {
    final prepared = <String, Map<String, dynamic>>{};
    final values = <({Decimal value, String? currency})>{};
    final toolAmounts = <int>{};
    const context = ParseContext(clock: Clock());
    for (final m in messages) {
      final role = m['role'];
      for (final part in _parts(m['content'])) {
        if (role == 'user' && part['text'] is String) {
          for (final a in parseText(part['text'] as String, context).amounts) {
            // A currency the parser only guessed does not constrain.
            values.add((
              value: a.value,
              currency: a.guessed ? null : a.currency?.code,
            ));
          }
        }
        final response = part['toolResponse'];
        if (response is Map) {
          // In process a tool's output is still its Dart object; its JSON
          // is what the model saw.
          final output = _plain(response['output']);
          if (response['name'] == prepareEntriesTool && output is Map) {
            // The latest call replaces the whole set.
            prepared.clear();
            for (final d in _list(output['drafts'])) {
              if (d is Map && d['id'] is String) {
                prepared[d['id'] as String] = d.cast<String, dynamic>();
              }
            }
          } else {
            _collectMinor(output, toolAmounts);
          }
        }
      }
    }
    return GuardFacts(
      preparedDrafts: prepared,
      messageValues: values,
      toolMinorAmounts: toolAmounts,
    );
  }

  /// Drafts of the latest `prepareEntries` result, by id.
  final Map<String, Map<String, dynamic>> preparedDrafts;

  /// Amounts the parser found in user messages, in major units, with the
  /// currency the words named (null when none).
  final Set<({Decimal value, String? currency})> messageValues;

  /// Minor-unit figures in other tool results.
  final Set<int> toolMinorAmounts;

  /// Why [raw] must be dropped, or null when it may stay.
  String? reject(Object? raw) {
    final check = checkDraft(raw, const HouseholdRefs());
    if (check.isMalformed) return 'malformed';
    final draft = check.draft!;
    final amount = draft.amountMinor;
    if (amount == null) return null;
    // A draft prepareEntries returned may carry only its own amount: other
    // figures from the message (another entry's) are not enough.
    if (preparedDrafts[draft.id] case final prepared?) {
      return prepared['amountMinor'] == amount &&
              prepared['currency'] == draft.currency
          ? null
          : 'unbacked_amount';
    }
    if (toolMinorAmounts.contains(amount)) return null;
    final currency = Currency.tryParse(draft.currency ?? '');
    if (currency != null) {
      final major = Decimal.parse(Money(amount, currency).toMajorString());
      final backed = messageValues.any(
        (m) =>
            m.value == major &&
            (m.currency == null || m.currency == currency.code),
      );
      if (backed) return null;
    }
    return 'unbacked_amount';
  }

  static void _collectMinor(Object? value, Set<int> out) {
    switch (value) {
      case final Map<Object?, Object?> map:
        for (final MapEntry(:key, :value) in map.entries) {
          if (key is String && key.endsWith('Minor') && value is int) {
            out.add(value);
          } else {
            _collectMinor(value, out);
          }
        }
      case final List<Object?> list:
        for (final v in list) {
          _collectMinor(v, out);
        }
    }
  }
}

/// One draft the guard removed.
@immutable
final class GuardViolation {
  /// Creates a record.
  const new({required this.surfaceId, required this.reason, this.draftId});

  /// The surface.
  final String surfaceId;

  /// The draft id, when readable.
  final String? draftId;

  /// `malformed` or `unbacked_amount`.
  final String reason;

  @override
  String toString() => 'GuardViolation($surfaceId/$draftId: $reason)';
}

/// Applies [facts] to the A2UI parts in [parts] (JSON form) and returns the
/// cleaned parts, what was removed, and whether anything changed (drafts
/// put back to the tool's version change parts without a violation). Parts
/// other than A2UI pass through.
({
  List<Map<String, dynamic>> parts,
  List<GuardViolation> violations,
  bool changed,
})
guardParts(List<Map<String, dynamic>> parts, GuardFacts facts) {
  final violations = <GuardViolation>[];
  final out = <Map<String, dynamic>>[];
  for (final part in parts) {
    final metadata = part['metadata'];
    final data = part['data'];
    if (metadata is! Map ||
        metadata['mimeType'] != a2uiMime ||
        data is! Map ||
        data['messages'] is! List) {
      out.add(part);
      continue;
    }
    // A figure in an answer surface that no tool returned: the whole
    // surface is dropped (its prose stays), because a component cannot be
    // removed without breaking the tree.
    final unbacked = _unbackedFigures(data['messages'] as List, facts);
    if (unbacked != null) {
      violations.add(
        GuardViolation(surfaceId: unbacked, reason: 'unbacked_figure'),
      );
      continue;
    }
    var express = metadata[a2uiExpressKey] as String?;
    final messages = <Object?>[];
    for (final message in data['messages'] as List) {
      final result = _guardMessage(message, facts, violations);
      if (result == null) {
        // An update that failed: drop it and its Express line.
        final update = (message as Map)['updateDataModel'] as Map;
        final path = update['path'];
        if (express != null) {
          express = rewriteAssignment(
            express,
            path is String ? path : '/',
            null,
          );
        }
        continue;
      }
      messages.add(result.message);
      if (result.rewritePath case final path? when express != null) {
        express = rewriteAssignment(express, path, jsonEncode(result.rewrite));
      }
    }
    out.add(<String, dynamic>{
      ...part,
      'data': <String, dynamic>{
        ...data.cast<String, dynamic>(),
        'messages': messages,
      },
      'metadata': <String, dynamic>{
        ...metadata.cast<String, dynamic>(),
        a2uiExpressKey: ?express,
      },
    });
  }
  return (
    parts: out,
    violations: violations,
    changed: jsonEncode(out) != jsonEncode(parts),
  );
}

/// Data-model keys whose contents are checked as drafts, not as figures.
const _draftKeys = {'drafts', 'receipt'};

/// The surface id of the first message holding a literal money figure (an
/// integer under a key ending in `Minor`) that is not in a tool result, or
/// null. Bound values (`{"@path": …}`) are not literals and pass.
String? _unbackedFigures(List<Object?> messages, GuardFacts facts) {
  for (final m in messages) {
    if (m is! Map) continue;
    final body = m['createSurface'] ?? m['updateComponents'];
    if (body is! Map) continue;
    final figures = <int>[];
    _figures(body['components'], figures);
    if (body['dataModel'] case final Map<Object?, Object?> model) {
      figures.addAll(_modelFigures(model));
    }
    if (!_figuresBacked(figures, facts)) return '${body['surfaceId']}';
  }
  return null;
}

/// Whether every figure in [figures] came from a tool result (or a
/// prepared draft); 0 is always allowed.
bool _figuresBacked(List<int> figures, GuardFacts facts) {
  final allowed = {
    0,
    ...facts.toolMinorAmounts,
    for (final d in facts.preparedDrafts.values)
      if (d['amountMinor'] case final int a) a,
  };
  return figures.every(allowed.contains);
}

/// The literal money figures of a whole data model, outside the drafts and
/// the receipt (checked as drafts). A top-level key names its scalar
/// (`$/totalMinor = …`).
List<int> _modelFigures(Map<Object?, Object?> model) {
  final figures = <int>[];
  for (final MapEntry(:key, :value) in model.entries) {
    if (!_draftKeys.contains(key)) {
      _figures(value, figures, key is String ? key : null);
    }
  }
  return figures;
}

void _figures(Object? value, List<int> out, [String? key]) {
  switch (value) {
    case final int n when key != null && key.endsWith('Minor'):
      out.add(n);
    case final Map<Object?, Object?> map:
      for (final MapEntry(:key, :value) in map.entries) {
        _figures(value, out, key is String ? key : null);
      }
    case final List<Object?> list:
      for (final v in list) {
        _figures(v, out, key);
      }
  }
}

/// The segments of a data-model path as the A2UI data model reads it:
/// empty segments dropped (`/drafts//0/`, `drafts/0` and `/drafts/0` are
/// one place) and `~1`, `~0` unescaped. An empty list is the whole model.
List<String> _segments(String? path) => [
  for (final s in (path ?? '').split('/'))
    if (s.isNotEmpty) s.replaceAll('~1', '/').replaceAll('~0', '~'),
];

/// What [_guardMessage] decided: the message to keep, and an Express
/// assignment to rewrite (`$<path> = <value as JSON>`) when its value
/// changed.
typedef _Guarded = ({Object? message, String? rewritePath, Object? rewrite});

/// Checks one A2UI message. Returns null when the whole message must be
/// dropped.
///
/// Drafts change only through `prepareEntries` (the capture rules: "never
/// change, reorder, drop or add a draft or any of its fields"), so every way
/// a message can write `/drafts` gets the same policy:
/// - a drafts array (in `createSurface`, at `/drafts`, or inside a
///   whole-model update) is filtered by [_filter];
/// - one whole draft (`/drafts/N`) is put back to the prepared draft with
///   its id, else checked by [GuardFacts.reject];
/// - one field of a draft (`/drafts/N/missing`, `/drafts/N/accountId`…)
///   is refused: it could clear what the tool asks the member to confirm,
///   or set a field the member never wrote.
_Guarded? _guardMessage(
  Object? message,
  GuardFacts facts,
  List<GuardViolation> violations,
) {
  final keep = (message: message, rewritePath: null, rewrite: null);
  if (message is! Map) return keep;
  final create = message['createSurface'];
  if (create is Map && create['dataModel'] is Map) {
    final model = create['dataModel'] as Map;
    final kept = _filterModel(
      model,
      facts,
      '${create['surfaceId']}',
      violations,
    );
    if (kept == null) return keep;
    return (
      message: <String, dynamic>{
        ...message.cast<String, dynamic>(),
        'createSurface': <String, dynamic>{
          ...create.cast<String, dynamic>(),
          'dataModel': kept,
        },
      },
      rewritePath: '/drafts',
      rewrite: kept['drafts'],
    );
  }
  final update = message['updateDataModel'];
  if (update is! Map) return keep;
  final path = update['path'] is String ? update['path'] as String : null;
  final segments = _segments(path);
  final surfaceId = '${update['surfaceId']}';
  final value = update['value'];
  Map<String, dynamic> withValue(Object? v) => <String, dynamic>{
    ...message.cast<String, dynamic>(),
    'updateDataModel': <String, dynamic>{
      ...update.cast<String, dynamic>(),
      'value': v,
    },
  };
  String? refuse(String reason) {
    violations.add(GuardViolation(surfaceId: surfaceId, reason: reason));
    return null;
  }

  // The whole data model: checked as a createSurface data model is.
  if (segments.isEmpty) {
    if (value is! Map) return keep;
    if (!_figuresBacked(_modelFigures(value), facts)) {
      refuse('unbacked_figure');
      return null;
    }
    final kept = _filterModel(value, facts, surfaceId, violations);
    if (kept == null) return keep;
    return (message: withValue(kept), rewritePath: path ?? '/', rewrite: kept);
  }
  if (segments.first != 'drafts') {
    // Any other path (an answer's `/result/…`): its money figures must come
    // from a tool, as in a createSurface.
    final figures = <int>[];
    _figures(value, figures, segments.last);
    if (!_figuresBacked(figures, facts)) {
      refuse('unbacked_figure');
      return null;
    }
    return keep;
  }
  switch (segments.length) {
    case 1:
      // A null clears the drafts; anything but an array is not drafts.
      if (value == null) return keep;
      if (value is! List) {
        refuse('malformed');
        return null;
      }
      final kept = _filter(value, facts, surfaceId, violations);
      if (_same(kept, value)) return keep;
      return (message: withValue(kept), rewritePath: path, rewrite: kept);
    case 2:
      if (_prepared(value, facts) case final prepared?) {
        if (_same([prepared], [value])) return keep;
        return (
          message: withValue(prepared),
          rewritePath: path,
          rewrite: prepared,
        );
      }
      if (facts.reject(value) case final reason?) {
        refuse(reason);
        return null;
      }
      return keep;
    default:
      refuse(
        const {'amountMinor', 'currency'}.contains(segments[2])
            ? 'amount_edit'
            : 'draft_edit',
      );
      return null;
  }
}

/// [model] (a whole data model) with its drafts filtered, or null when it
/// has no drafts array or every draft passed unchanged.
Map<String, dynamic>? _filterModel(
  Map<dynamic, dynamic> model,
  GuardFacts facts,
  String surfaceId,
  List<GuardViolation> violations,
) {
  final drafts = model['drafts'];
  if (drafts is! List) return null;
  final kept = _filter(drafts, facts, surfaceId, violations);
  if (_same(kept, drafts)) return null;
  return <String, dynamic>{...model.cast<String, dynamic>(), 'drafts': kept};
}

/// The drafts a surface may show: a draft whose id `prepareEntries`
/// returned is replaced by the tool's exact draft (the model drops or
/// rewrites fields when it copies: confidence, guessed, recurring, missing);
/// any other draft is kept only when [GuardFacts.reject] passes it. A
/// second draft with an id already shown is dropped: saved, it would record
/// the same entry twice.
List<Object?> _filter(
  List<Object?> drafts,
  GuardFacts facts,
  String surfaceId,
  List<GuardViolation> violations,
) {
  final ids = <Object?>{};
  return [
    for (final d in drafts)
      if (d is Map && d['id'] != null && !ids.add(d['id']))
        ..._record(violations, surfaceId, d, 'duplicate_draft')
      else if (_prepared(d, facts) case final prepared?)
        prepared
      else if (facts.reject(d) case final reason?)
        ..._record(violations, surfaceId, d, reason)
      else
        d,
  ];
}

Map<String, dynamic>? _prepared(Object? draft, GuardFacts facts) =>
    draft is Map ? facts.preparedDrafts[draft['id']] : null;

/// Whether two draft lists are the same JSON (key order included).
bool _same(List<Object?> a, List<Object?> b) => jsonEncode(a) == jsonEncode(b);

List<Object?> _record(
  List<GuardViolation> violations,
  String surfaceId,
  Object? draft,
  String reason,
) {
  violations.add(
    GuardViolation(
      surfaceId: surfaceId,
      draftId: draft is Map ? draft['id']?.toString() : null,
      reason: reason,
    ),
  );
  return const [];
}

/// Rewrites the Express assignment to [path] (`$/drafts`, `$/drafts/1`…)
/// in [source]: replaces its value with [valueJson], or removes the whole
/// assignment when [valueJson] is null. Returns [source] unchanged when no
/// such assignment exists. The value may span lines; brackets inside
/// strings are skipped.
String rewriteAssignment(String source, String path, String? valueJson) {
  final escaped = RegExp.escape('\$$path');
  final start = RegExp(
    '^[ \\t]*$escaped[ \\t]*=[ \\t]*',
    multiLine: true,
  ).firstMatch(source);
  if (start == null) return source;
  final valueStart = start.end;
  final valueEnd = _valueEnd(source, valueStart);
  if (valueJson == null) {
    var end = valueEnd;
    if (end < source.length && source[end] == '\n') end++;
    return source.replaceRange(start.start, end, '');
  }
  return source.replaceRange(valueStart, valueEnd, valueJson);
}

int _valueEnd(String s, int from) {
  var depth = 0;
  var i = from;
  while (i < s.length) {
    final c = s[i];
    if (c == '"') {
      final triple = s.startsWith('"""', i);
      final close = triple ? '"""' : '"';
      i += close.length;
      while (i < s.length && !s.startsWith(close, i)) {
        if (s[i] == r'\' && !triple) i++;
        i++;
      }
      i += close.length;
      continue;
    }
    if (c == '[' || c == '{' || c == '(') depth++;
    if (c == ']' || c == '}' || c == ')') depth--;
    if (c == '\n' && depth <= 0) return i;
    i++;
    if (depth == 0 && (c == ']' || c == '}' || c == ')')) {
      // The value ends at the line's end after its closing bracket.
      final nl = s.indexOf('\n', i);
      return nl < 0 ? s.length : nl;
    }
  }
  return s.length;
}

Object? _plain(Object? value) =>
    value == null || value is num || value is String || value is bool
    ? value
    : jsonDecode(jsonEncode(value));

Iterable<Map<String, dynamic>> _parts(Object? content) sync* {
  for (final p in _list(content)) {
    if (p is Map) yield p.cast<String, dynamic>();
  }
}

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];
