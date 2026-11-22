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
    final prepared = preparedDrafts[draft.id];
    if (prepared != null &&
        prepared['amountMinor'] == amount &&
        prepared['currency'] == draft.currency) {
      return null;
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
        // An element update that failed: drop it and its Express line.
        final update = (message as Map)['updateDataModel'] as Map;
        if (express != null) {
          express = rewriteAssignment(express, update['path'] as String, null);
        }
        continue;
      }
      messages.add(result.message);
      if (result.keptDrafts != null && express != null) {
        express = rewriteAssignment(
          express,
          result.draftsPath!,
          jsonEncode(result.keptDrafts),
        );
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
    final model = body['dataModel'];
    if (model is Map) {
      for (final MapEntry(:key, :value) in model.entries) {
        if (!_draftKeys.contains(key)) _figures(value, figures);
      }
    }
    final allowed = {
      0,
      ...facts.toolMinorAmounts,
      for (final d in facts.preparedDrafts.values)
        if (d['amountMinor'] case final int a) a,
    };
    if (figures.any((f) => !allowed.contains(f))) {
      return '${body['surfaceId']}';
    }
  }
  return null;
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

final _elementPath = RegExp(r'^/drafts/(\d+)(/.*)?$');

/// Checks one A2UI message. Returns null when the whole message must be
/// dropped; `keptDrafts` is set when a drafts array was filtered.
({Object? message, List<Object?>? keptDrafts, String? draftsPath})?
_guardMessage(
  Object? message,
  GuardFacts facts,
  List<GuardViolation> violations,
) {
  if (message is! Map) {
    return (message: message, keptDrafts: null, draftsPath: null);
  }
  final create = message['createSurface'];
  if (create is Map && create['dataModel'] is Map) {
    final model = create['dataModel'] as Map;
    final drafts = model['drafts'];
    if (drafts is List) {
      final kept = _filter(drafts, facts, '${create['surfaceId']}', violations);
      if (_same(kept, drafts)) {
        return (message: message, keptDrafts: null, draftsPath: null);
      }
      return (
        message: <String, dynamic>{
          ...message.cast<String, dynamic>(),
          'createSurface': <String, dynamic>{
            ...create.cast<String, dynamic>(),
            'dataModel': <String, dynamic>{
              ...model.cast<String, dynamic>(),
              'drafts': kept,
            },
          },
        },
        keptDrafts: kept,
        draftsPath: '/drafts',
      );
    }
  }
  final update = message['updateDataModel'];
  if (update is Map && update['path'] is String) {
    final path = update['path'] as String;
    final surfaceId = '${update['surfaceId']}';
    if (path == '/drafts' && update['value'] is List) {
      final drafts = update['value'] as List;
      final kept = _filter(drafts, facts, surfaceId, violations);
      if (_same(kept, drafts)) {
        return (message: message, keptDrafts: null, draftsPath: null);
      }
      return (
        message: <String, dynamic>{
          ...message.cast<String, dynamic>(),
          'updateDataModel': <String, dynamic>{
            ...update.cast<String, dynamic>(),
            'value': kept,
          },
        },
        keptDrafts: kept,
        draftsPath: '/drafts',
      );
    }
    final element = _elementPath.firstMatch(path);
    if (element != null) {
      final rest = element.group(2);
      // A whole draft: re-check it. Its amount or currency alone: refused;
      // the prompt has the agent re-run prepareEntries and re-render.
      final reason = rest == null ? facts.reject(update['value']) : null;
      if (reason != null) {
        violations.add(GuardViolation(surfaceId: surfaceId, reason: reason));
        return null;
      }
      if (rest == '/amountMinor' || rest == '/currency') {
        violations.add(
          GuardViolation(surfaceId: surfaceId, reason: 'amount_edit'),
        );
        return null;
      }
    }
  }
  return (message: message, keptDrafts: null, draftsPath: null);
}

/// The drafts a surface may show: a draft whose id `prepareEntries`
/// returned is replaced by the tool's exact draft (the model drops or
/// rewrites fields when it copies: confidence, guessed, recurring); any
/// other draft is kept only when [GuardFacts.reject] passes it.
List<Object?> _filter(
  List<Object?> drafts,
  GuardFacts facts,
  String surfaceId,
  List<GuardViolation> violations,
) => [
  for (final d in drafts)
    if (_prepared(d, facts) case final prepared?)
      prepared
    else if (facts.reject(d) case final reason?)
      ..._record(violations, surfaceId, d, reason)
    else
      d,
];

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
