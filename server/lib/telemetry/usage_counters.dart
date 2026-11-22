/// Per-household daily AI usage counters (`households/{hid}/usage/{day}`).
///
/// DATA_MODEL 2.15: `{agentTurns, decisions, audioSeconds, images,
/// inputTokens, outputTokens, costMicrosUsd}`. The context provider reads them
/// to enforce the limits in `config/runtime`; the routes that do metered work
/// (`/agent`, `/decide`) add to them after the work is done.
library;

import 'package:clock/clock.dart';

import 'package:xpense_agent/admin/admin_gateway.dart';

/// One counter in the usage document.
enum UsageCounter {
  /// Agent turns (`/agent`).
  agentTurns('agentTurns'),

  /// Decisions API calls (`/decide`).
  decisions('decisions'),

  /// Seconds of audio sent to the agent.
  audioSeconds('audioSeconds'),

  /// Images sent to the agent.
  images('images'),

  /// Model input tokens.
  inputTokens('inputTokens'),

  /// Model output tokens.
  outputTokens('outputTokens'),

  /// Estimated model cost in millionths of a US dollar (integer, never a
  /// double: rule 5).
  costMicrosUsd('costMicrosUsd');

  new(this.field);

  /// The Firestore field name.
  final String field;

  /// The counter stored under [field], or null.
  static UsageCounter? byField(String field) {
    for (final counter in values) {
      if (counter.field == field) return counter;
    }
    return null;
  }
}

/// Reads and adds to a household's counters for the current day.
///
/// A day is a UTC calendar day (`yyyy-mm-dd`), so the limits reset at 03:00
/// in Baghdad. UTC keeps the key independent of each household's time zone
/// and of server-side time-zone data.
final class UsageCounters {
  /// Creates counters over a [DocumentStore].
  new(this._documents, {Clock? clock}) : _clock = clock ?? const Clock();

  final DocumentStore _documents;
  final Clock _clock;

  /// The usage document id for [at]: its UTC date.
  static String dayKey(DateTime at) {
    final utc = at.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
        '${two(utc.day)}';
  }

  /// The usage document path for household [hid] at [at].
  static String pathFor(String hid, DateTime at) =>
      'households/$hid/usage/${dayKey(at)}';

  /// Today's counters for [hid]. Missing counters are 0.
  Future<Map<UsageCounter, int>> today(String hid) async {
    final doc = await _documents.read(pathFor(hid, _clock.now()));
    return {
      for (final counter in UsageCounter.values)
        counter: switch (doc?[counter.field]) {
          final int n => n,
          final num n => n.toInt(),
          _ => 0,
        },
    };
  }

  /// Adds [amounts] to today's counters for [hid] in one atomic write.
  /// Zero amounts are skipped; negative amounts are a programming error.
  Future<void> add(String hid, Map<UsageCounter, int> amounts) async {
    if (amounts.values.any((v) => v < 0)) {
      throw ArgumentError.value(amounts, 'amounts', 'must not be negative');
    }
    final deltas = {
      for (final MapEntry(:key, :value) in amounts.entries)
        if (value != 0) key.field: value,
    };
    if (deltas.isEmpty) return;
    final now = _clock.now();
    await _documents.increment(
      pathFor(hid, now),
      deltas,
      fields: {
        'day': dayKey(now),
        'updatedAt': now.toUtc(),
        'updatedBy': 'system',
        'schemaVersion': 1,
      },
    );
  }

  /// The counters in [meters] that have reached their limit in [limits].
  /// Counters without a limit are never over.
  static Set<UsageCounter> overLimit({
    required Map<UsageCounter, int> usage,
    required Map<UsageCounter, int> limits,
    required Set<UsageCounter> meters,
  }) => {
    for (final counter in meters)
      if (limits[counter] case final limit? when (usage[counter] ?? 0) >= limit)
        counter,
  };
}
