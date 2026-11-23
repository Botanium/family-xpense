/// What backs amounts in an audio or image turn (AI_PIPELINE 8 rule 7).
///
/// A voice note or a receipt photo carries no text the member typed, so the
/// "amounts must be in the member's words" rule of `prepareEntries` has
/// nothing to check against. In such a turn the agent first shows the
/// member what it read: a `Transcript` component, or a `ReceiptSummary`
/// with the receipt in its data model. Those, as emitted after `outputGuard`
/// in this same turn, back the amounts; anything else stays a provisional
/// figure the member must confirm.
///
/// This is the minimum WP-32 needs so that media turns do not lose every
/// amount. Speech recognition, receipt OCR, the on-device transcript path
/// and their own checks are WP-40 (voice) and WP-41 (receipts).
///
/// One [TurnEvidence] lives for one agent turn. `householdContext` creates
/// it around the turn's generate loop and runs the loop in a zone holding
/// it; `outputGuard` records what each model call showed; the tools read it
/// through [TurnEvidence.current]. The session cannot serve here: it holds
/// the turn's model output only once the turn has ended.
library;

import 'dart:async';

import 'package:xpense_shared/xpense_shared.dart';

const _zoneKey = #xpenseTurnEvidence;

/// The MIME type of A2UI data parts.
const _a2uiMime = 'application/a2ui+json';

/// Media and what the agent showed of it, for one turn.
final class TurnEvidence {
  /// Creates empty evidence; [mediaTurn] says a member message of the
  /// session carries audio or an image, [latestMedia] that the latest one
  /// does.
  new({this.mediaTurn = false, bool? latestMedia})
    : latestMedia = latestMedia ?? mediaTurn;

  /// The evidence of the running turn, or null outside one.
  static TurnEvidence? get current => Zone.current[_zoneKey] as TurnEvidence?;

  /// Whether a member message of the session carries audio or an image.
  final bool mediaTurn;

  /// Whether the latest member message carries audio or an image: its
  /// transcript, not earlier typed text, is then the latest member words.
  final bool latestMedia;

  /// Texts shown to the member this turn: transcripts, and the figures of
  /// a receipt written as words the fast parser reads ("12.50 dollars").
  /// They back amounts.
  final List<String> shownTexts = [];

  /// The transcripts alone: what the member said, shown back to them.
  /// They count as the member's words for dates, account, category and
  /// person words, and the classifier's description, like typed text. A
  /// receipt's figures do not: they are not the member's words.
  final List<String> transcripts = [];

  /// Runs [body] with this evidence as [current].
  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_zoneKey: this});

  /// Whether [message] (JSON form) carries audio or an image.
  static bool hasMedia(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is! List) return false;
    return content.any((p) => p is Map && p['media'] is Map);
  }

  /// Records the `Transcript` texts and `ReceiptSummary` receipts in
  /// [parts] (a model response's content, JSON form, after `outputGuard`,
  /// or an earlier model message of the session).
  void recordShown(List<Map<String, dynamic>> parts) {
    for (final part in parts) {
      final metadata = part['metadata'];
      final data = part['data'];
      // A session's history keeps the A2UI messages but not the part's
      // metadata; a part marked as something else is skipped.
      if (metadata is Map && metadata['mimeType'] != _a2uiMime) continue;
      if (data is! Map || data['messages'] is! List) continue;
      for (final m in data['messages'] as List) {
        if (m is! Map) continue;
        final body = m['createSurface'] ?? m['updateComponents'];
        if (body is! Map) continue;
        final model = body['dataModel'] is Map
            ? (body['dataModel'] as Map).cast<String, dynamic>()
            : const <String, dynamic>{};
        for (final c
            in body['components'] is List
                ? body['components'] as List
                : const <Object?>[]) {
          if (c is! Map) continue;
          switch (c['component']) {
            case 'Transcript':
              if (_resolve(c['text'], model) case final String text) {
                shownTexts.add(text);
                transcripts.add(text);
              }
            case 'ReceiptSummary':
              if (_resolve(c['receipt'], model)
                  case final Map<Object?, Object?> receipt) {
                _recordReceipt(receipt);
              }
          }
        }
      }
    }
  }

  void _recordReceipt(Map<Object?, Object?> receipt) {
    final currency = Currency.tryParse('${receipt['currency']}');
    if (currency == null) return;
    // Written as words the parser reads, so the figures enter the same
    // amount pool as the member's own text.
    final word = currency == Currency.iqd ? 'dinars' : 'dollars';
    String said(Object? minor) =>
        minor is int ? '${Money(minor, currency).toMajorString()} $word' : '';
    shownTexts.add(
      [
        said(receipt['totalMinor']),
        if (receipt['lines'] case final List<Object?> lines)
          for (final line in lines)
            if (line is Map) said(line['amountMinor']),
      ].where((s) => s.isNotEmpty).join(' and '),
    );
  }

  /// A literal, or a value bound by `{"@path": "/a/b"}` into [model].
  static Object? _resolve(Object? value, Map<String, dynamic> model) {
    if (value is! Map || value['@path'] is! String) return value;
    Object? at = model;
    for (final key in (value['@path'] as String).split('/')) {
      if (key.isEmpty) continue;
      at = switch (at) {
        final Map<dynamic, dynamic> m => m[key],
        final List<Object?> l when int.tryParse(key) != null =>
          int.parse(key) < l.length ? l[int.parse(key)] : null,
        _ => null,
      };
    }
    return at;
  }
}
