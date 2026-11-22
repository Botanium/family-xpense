/// The local surface builder (A2UI_CATALOG 8, story S3.5).
///
/// Pure Dart, no `a2ui_core`: every builder returns A2UI v1.0 messages as
/// plain spec-shaped maps, ready for `MessageProcessor.processMessages` on
/// the phone, and runnable on the server for tests, evaluations and
/// deterministic surfaces in jobs. Each builder returns one `createSurface`
/// carrying the components and the data model together.
///
/// Rules (WP-S1): bindings are written `{"@path": …}`; surface ids start
/// with [localSurfacePrefix]; actions start with [localActionPrefix]. The
/// builders hold no user-visible words of their own: callers pass every
/// string, already localised.
library;

import 'dart:convert';

import 'package:xpense_shared/catalog/xpense_catalog.dart';
import 'package:xpense_shared/schema/entry_draft.dart';
import 'package:xpense_shared/surface/local_surfaces.dart';

/// Most drafts one surface may carry (A2UI_CATALOG 9).
const int maxDraftsPerSurface = 20;

/// What the phone heard or read, shown by a `Transcript`.
final class TranscriptData {
  /// Creates transcript data.
  const new({required this.text, this.seconds});

  /// The words, without quotation marks.
  final String text;

  /// Recording length in whole seconds; null for typed messages.
  final int? seconds;
}

/// One answer of a [ChoicePromptData].
final class ChoiceOptionData {
  /// Creates an option.
  const new({required this.label, required this.value, this.hint});

  /// The answer as shown.
  final String label;

  /// The value written to [ChoicePromptData.path] when picked.
  final String value;

  /// A short line under the label.
  final String? hint;

  /// The option as the catalog's `options` item.
  Map<String, Object?> toJson() => {
    'label': label,
    'value': value,
    'hint': ?hint,
  };
}

/// A question whose answer changes a draft's meaning, such as the intent of
/// "Gave Alex 300". Ordinary missing fields are asked by `EntryList` itself.
final class ChoicePromptData {
  /// Creates a question that writes the picked value to [path].
  const new({
    required this.question,
    required this.options,
    required this.path,
    this.allowOther = false,
  });

  /// A question about the intent of the draft at [draftIndex].
  factory intent({
    required String question,
    required List<ChoiceOptionData> options,
    int draftIndex = 0,
  }) => ChoicePromptData(
    question: question,
    options: options,
    path: '${SurfacePaths.drafts}/$draftIndex/intent',
  );

  /// The question, one sentence.
  final String question;

  /// Two to five answers.
  final List<ChoiceOptionData> options;

  /// The data-model path the pick is written to.
  final String path;

  /// Whether to offer "Other…" with a text field.
  final bool allowOther;
}

/// A receipt as `ReceiptSummary` reads it from `/receipt`.
final class SurfaceReceipt {
  /// Creates a receipt.
  const new({
    required this.merchant,
    required this.occurredOn,
    required this.currency,
    required this.totalMinor,
    this.occurredTime,
    this.lines = const [],
  });

  /// Merchant name.
  final String merchant;

  /// Household-local date, `YYYY-MM-DD`.
  final String occurredOn;

  /// Household-local time, `HH:mm`.
  final String? occurredTime;

  /// ISO currency code.
  final String currency;

  /// Total in minor units of [currency].
  final int totalMinor;

  /// Line items.
  final List<SurfaceReceiptLine> lines;

  /// The receipt as the data model holds it.
  Map<String, Object?> toJson() => {
    'merchant': merchant,
    'occurredOn': occurredOn,
    'occurredTime': ?occurredTime,
    'currency': currency,
    'totalMinor': totalMinor,
    'lines': [for (final line in lines) line.toJson()],
  };
}

/// One line of a [SurfaceReceipt].
final class SurfaceReceiptLine {
  /// Creates a line.
  const new({required this.text, required this.amountMinor, this.categoryId});

  /// The line as printed.
  final String text;

  /// Amount in minor units.
  final int amountMinor;

  /// The category it was filed under, if known.
  final String? categoryId;

  /// The line as the data model holds it.
  Map<String, Object?> toJson() => {
    'text': text,
    'amountMinor': amountMinor,
    'categoryId': ?categoryId,
  };
}

/// An action handled on the phone; its wire name is
/// `xp.local.<name>` (A2UI_CATALOG 5.1).
final class LocalAction {
  /// Creates an action named [name] (one of [LocalActionNames]).
  const new(this.name, {this.context = const {}});

  /// The name without the prefix.
  final String name;

  /// Values passed with the action.
  final Map<String, Object?> context;

  /// The action as a catalog `Action`.
  Map<String, Object?> toJson() => {
    'event': {
      'name': '$localActionPrefix$name',
      if (context.isNotEmpty) 'context': context,
    },
  };
}

/// What a `Nudge` is about.
enum NudgeKind {
  /// A bill that is usually paid by now.
  bill,

  /// A budget near or over its limit.
  budget,

  /// A loan due soon.
  loan,

  /// Today's exchange rate is missing.
  rate,

  /// A report is ready.
  report,

  /// Anything else.
  info,
}

/// What went wrong, for a `Notice`.
enum NoticeKind {
  /// No connection.
  offline,

  /// A usage limit was reached.
  limit,

  /// The privacy mode prevents it.
  privacy,

  /// Anything else.
  error,
}

/// Tone of a `SavedNote`.
enum SavedTone {
  /// After a save.
  ok,

  /// A fact.
  info,

  /// A problem.
  warn,
}

/// Where a receipt was read.
enum ReceiptSource {
  /// On the phone.
  device,

  /// By the agent.
  cloud,
}

/// A capture: the transcript (if any), an intent question (if any) and the
/// drafts in an `EntryList` bound to `/drafts`.
List<Map<String, Object?>> captureSurface({
  required String surfaceId,
  required List<EntryDraft> drafts,
  String? title,
  TranscriptData? transcript,
  ChoicePromptData? ask,
}) {
  _checkDrafts(drafts);
  if (ask != null) _checkAsk(ask);
  return _create(
    surfaceId,
    components: [
      _column([
        if (transcript != null) 'heard',
        if (ask != null) 'ask',
        'list',
      ]),
      if (transcript != null) _transcript(transcript),
      if (ask != null)
        {
          'id': 'ask',
          'component': 'ChoicePrompt',
          'question': ask.question,
          'options': [for (final o in ask.options) o.toJson()],
          'value': _bind(ask.path),
          if (ask.allowOther) 'allowOther': true,
        },
      {
        'id': 'list',
        'component': 'EntryList',
        'drafts': _bind(SurfacePaths.drafts),
        'status': 'review',
        'title': ?title,
      },
    ],
    dataModel: {'drafts': _draftsJson(drafts)},
  );
}

/// A scanned receipt: `ReceiptSummary` bound to `/receipt`, `/drafts` and
/// the `/ui/split` switch.
List<Map<String, Object?>> receiptSurface({
  required String surfaceId,
  required SurfaceReceipt receipt,
  required List<EntryDraft> drafts,
  bool split = false,
  ReceiptSource source = ReceiptSource.device,
}) {
  _checkDrafts(drafts);
  return _create(
    surfaceId,
    components: [
      {
        'id': 'root',
        'component': 'ReceiptSummary',
        'receipt': _bind(SurfacePaths.receipt),
        'drafts': _bind(SurfacePaths.drafts),
        'split': _bind(SurfacePaths.split),
        'source': source.name,
      },
    ],
    dataModel: {
      'receipt': receipt.toJson(),
      'drafts': _draftsJson(drafts),
      'ui': {'split': split},
    },
  );
}

/// A proactive line with at most one local action.
List<Map<String, Object?>> nudgeSurface({
  required String surfaceId,
  required String text,
  required NudgeKind kind,
  String? actionLabel,
  LocalAction? action,
}) => _create(
  surfaceId,
  components: [
    {
      'id': 'root',
      'component': 'Nudge',
      'text': text,
      'kind': kind.name,
      'actionLabel': ?actionLabel,
      'action': ?action?.toJson(),
    },
  ],
);

/// A placeholder for a capture waiting in the offline queue: what was heard
/// and an `offline` notice.
List<Map<String, Object?>> queuedSurface({
  required String surfaceId,
  required TranscriptData heard,
  required String text,
  String? actionLabel,
  LocalAction? action,
}) => _create(
  surfaceId,
  components: [
    _column(['heard', 'notice']),
    _transcript(heard),
    _notice(NoticeKind.offline, text, actionLabel, action),
  ],
);

/// An error or limit in plain words.
List<Map<String, Object?>> noticeSurface({
  required String surfaceId,
  required String text,
  required NoticeKind kind,
  String? actionLabel,
  LocalAction? action,
}) => _create(
  surfaceId,
  components: [
    {..._notice(kind, text, actionLabel, action), 'id': 'root'},
  ],
);

/// A one-line confirmation.
List<Map<String, Object?>> savedSurface({
  required String surfaceId,
  required String text,
  SavedTone tone = SavedTone.ok,
}) => _create(
  surfaceId,
  components: [
    {'id': 'root', 'component': 'SavedNote', 'text': text, 'tone': tone.name},
  ],
);

List<Map<String, Object?>> _create(
  String surfaceId, {
  required List<Map<String, Object?>> components,
  Map<String, Object?>? dataModel,
}) {
  if (!isLocalSurfaceId(surfaceId) || !surfaceIdPattern.hasMatch(surfaceId)) {
    throw ArgumentError.value(
      surfaceId,
      'surfaceId',
      'must start with "$localSurfacePrefix" and use only letters, digits '
          'and underscores',
    );
  }
  return [
    {
      'version': xpenseProtocolVersion,
      'createSurface': {
        'surfaceId': surfaceId,
        'catalogId': xpenseCatalogId,
        'components': components,
        'dataModel': ?dataModel,
      },
    },
  ];
}

Map<String, Object?> _bind(String path) => {'@path': path};

Map<String, Object?> _column(List<String> children) => {
  'id': 'root',
  'component': 'Column',
  'children': children,
};

Map<String, Object?> _transcript(TranscriptData t) => {
  'id': 'heard',
  'component': 'Transcript',
  'text': t.text,
  'seconds': ?t.seconds,
};

Map<String, Object?> _notice(
  NoticeKind kind,
  String text,
  String? actionLabel,
  LocalAction? action,
) => {
  'id': 'notice',
  'component': 'Notice',
  'text': text,
  'kind': kind.name,
  'actionLabel': ?actionLabel,
  'action': ?action?.toJson(),
};

/// Deep copies, so the messages never alias a draft's own map.
List<Object?> _draftsJson(List<EntryDraft> drafts) =>
    jsonDecode(jsonEncode([for (final d in drafts) d.toJson()]))
        as List<Object?>;

void _checkDrafts(List<EntryDraft> drafts) {
  if (drafts.isEmpty || drafts.length > maxDraftsPerSurface) {
    throw ArgumentError.value(
      drafts.length,
      'drafts',
      'must hold 1 to $maxDraftsPerSurface drafts',
    );
  }
  final ids = {for (final d in drafts) d.id};
  if (ids.length != drafts.length) {
    throw ArgumentError.value(ids, 'drafts', 'draft ids must be unique');
  }
}

void _checkAsk(ChoicePromptData ask) {
  if (ask.options.length < 2 || ask.options.length > 5) {
    throw ArgumentError.value(
      ask.options.length,
      'ask.options',
      'must hold 2 to 5 options',
    );
  }
  if (!ask.path.startsWith('/')) {
    throw ArgumentError.value(ask.path, 'ask.path', 'must be absolute');
  }
}
