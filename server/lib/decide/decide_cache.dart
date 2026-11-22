/// The 10-minute LRU cache in front of the Decisions API (AI_PIPELINE 7).
///
/// WP-S4 found the API deterministic (two passes, 439 answers, no change),
/// so a repeat of the same request can be answered from memory. The key is
/// the household, the speaker, the duplicate candidates' ids and the exact
/// request body, which holds the date, the message, every option and every
/// candidate's description: any change to the household's lists, a new day
/// or a different candidate is a different key. Only calibrated
/// Decisions answers are stored, never fallback or unavailable responses.
library;

import 'package:clock/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A small in-memory LRU with a time to live. Per instance; Cloud Run
/// instances do not share it.
final class DecideCache {
  /// Creates a cache.
  new({
    this.ttl = const Duration(minutes: 10),
    this.capacity = 500,
    Clock? clock,
  }) : _clock = clock ?? const Clock();

  /// How long an answer is kept.
  final Duration ttl;

  /// The most entries kept; the least recently used goes first.
  final int capacity;

  final Clock _clock;
  final _entries = <String, (DateTime, DecideResponse)>{};

  /// The number of live and expired entries held.
  int get length => _entries.length;

  /// The key for one request.
  static String keyFor({
    required String hid,
    required String uid,
    required String body,
    List<String> candidateIds = const [],
  }) => [hid, uid, candidateIds.join(','), body].join('\u0000');

  /// The cached response for [key], or null.
  DecideResponse? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (!_clock.now().isBefore(entry.$1)) return null;
    _entries[key] = entry;
    return entry.$2;
  }

  /// Stores [response] under [key].
  void put(String key, DecideResponse response) {
    _entries
      ..remove(key)
      ..[key] = (_clock.now().add(ttl), response);
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }
}
