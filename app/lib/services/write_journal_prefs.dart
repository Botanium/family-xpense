// The [WriteJournal] in SharedPreferences: one JSON list under one key.
// Only the composition root names this file.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:xpense_app/services/write_journal.dart';

/// [WriteJournal] over SharedPreferences.
final class PrefsWriteJournal implements WriteJournal {
  new _(this._prefs, this._entries);

  /// The key the records are stored under.
  static const String key = 'ledger.pendingRevisions';

  /// Opens the journal and reads what an earlier run left.
  static Future<PrefsWriteJournal> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(allowList: {key}),
    );
    final entries = <PendingRevision>[];
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          entries.addAll(list.map(PendingRevision.fromJson).nonNulls);
        }
      } on FormatException {
        // A damaged journal is dropped; the changes it held were queued in
        // Firestore anyway.
      }
    }
    return PrefsWriteJournal._(prefs, entries);
  }

  final SharedPreferencesWithCache _prefs;
  final List<PendingRevision> _entries;

  @override
  List<PendingRevision> get entries => List.unmodifiable(_entries);

  @override
  Future<void> put(PendingRevision entry) async {
    _entries.add(entry);
    await _save();
  }

  @override
  Future<void> remove(String revId) async {
    final before = _entries.length;
    _entries.removeWhere((e) => e.revId == revId);
    if (_entries.length != before) await _save();
  }

  Future<void> _save() =>
      _prefs.setString(key, jsonEncode([for (final e in _entries) e.toJson()]));
}
