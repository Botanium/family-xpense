// Learned rules (ARCHITECTURE 5.7, DATA_MODEL 2.12, story S3.11).
//
// A guessed field the member corrects becomes a rule; the fast parser reads
// the rule cache on the next message, so the same merchant resolves on the
// phone (path L). This file is the interface and the in-memory store; the
// Firestore adapter is `rules_repository_firestore.dart`, named only by the
// composition root and tests.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What one correction teaches: when [pattern] appears, set the fields
/// given.
@immutable
final class RuleLesson {
  /// Creates a lesson. [pattern] is normalised by [RulesRepository.learn].
  const new({
    required this.kind,
    required this.pattern,
    this.categoryId,
    this.accountId,
    this.who,
    this.intent,
    this.fromTxnId,
  });

  /// What the pattern names.
  final RuleKind kind;

  /// The merchant, person or keyword, as written.
  final String pattern;

  /// The category to set.
  final String? categoryId;

  /// The account to set.
  final String? accountId;

  /// `me`, `partner` or `joint`.
  final String? who;

  /// The intent wire value to set.
  final String? intent;

  /// The saved transaction the lesson came from.
  final String? fromTxnId;

  /// Whether the lesson sets anything.
  bool get isEmpty =>
      categoryId == null && accountId == null && who == null && intent == null;

  @override
  bool operator ==(Object other) =>
      other is RuleLesson &&
      other.kind == kind &&
      other.pattern == pattern &&
      other.categoryId == categoryId &&
      other.accountId == accountId &&
      other.who == who &&
      other.intent == intent &&
      other.fromTxnId == fromTxnId;

  @override
  int get hashCode =>
      Object.hash(kind, pattern, categoryId, accountId, who, intent, fromTxnId);

  @override
  String toString() =>
      'RuleLesson(${kind.wire} "$pattern": category $categoryId, '
      'account $accountId, who $who, intent $intent)';
}

/// The normalised pattern a rule is stored under: lower case, single
/// spaces, as the parser matches it.
String rulePattern(String text) => normalizeText(text).trim();

/// A stable rule id for [kind] and [pattern], so learning the same pattern
/// again updates one rule instead of adding another. Firestore-safe:
/// `[a-z0-9_]`, at most 120 characters. The readable slug drops what is
/// not ASCII ("café" and "cafè" both give `caf`), so the id ends with 8 hex
/// of the SHA-256 of the whole normalised pattern, and different patterns
/// never share a rule.
String ruleIdFor(RuleKind kind, String pattern) {
  final normalised = rulePattern(pattern);
  final hash = sha256
      .convert(utf8.encode(normalised))
      .toString()
      .substring(0, 8);
  var slug = normalised
      .replaceAll(RegExp('[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty) slug = 'x';
  // Room for the kind, two underscores and the hash.
  final room = 120 - kind.wire.length - 2 - hash.length;
  if (slug.length > room) slug = slug.substring(0, room);
  return '${kind.wire}_${slug}_$hash';
}

/// [rule] with the fields [lesson] sets replaced; the rest kept.
ParserRule mergeLesson(ParserRule? rule, RuleLesson lesson) => ParserRule(
  id: rule?.id ?? ruleIdFor(lesson.kind, lesson.pattern),
  kind: lesson.kind,
  pattern: rulePattern(lesson.pattern),
  categoryId: lesson.categoryId ?? rule?.categoryId,
  accountId: lesson.accountId ?? rule?.accountId,
  who: lesson.who ?? rule?.who,
  intent: lesson.intent ?? rule?.intent,
);

/// The member's learned rules: a cache the parser reads synchronously, and
/// the one write path for new lessons.
abstract interface class RulesRepository {
  /// The rules known now, for the parser. Never blocks.
  List<ParserRule> get current;

  /// Emits the whole rule list whenever it changes.
  Stream<List<ParserRule>> watch();

  /// Creates the rule for [lesson], or updates the existing one (fields
  /// set, `hits` + 1). Empty lessons are ignored. Throws what the store
  /// throws; callers log it, since a lost lesson costs one more question
  /// next time, never data.
  Future<void> learn(RuleLesson lesson);
}

/// The [RulesRepository] for this run. Throws until the composition root
/// sets it.
final rulesRepositoryProvider = Provider<RulesRepository>(
  (ref) =>
      throw UnimplementedError('rulesRepositoryProvider is set in bootstrap()'),
  name: 'rulesRepositoryProvider',
);

/// Rules kept in memory for this run: the `fakes` environment and tests,
/// and the store until the household id is known (WP-12).
final class MemoryRulesRepository implements RulesRepository {
  /// Starts with [rules].
  new([List<ParserRule> rules = const []])
    : _rules = {for (final r in rules) r.id: r};

  final Map<String, ParserRule> _rules;
  final StreamController<List<ParserRule>> _changes =
      StreamController<List<ParserRule>>.broadcast();

  /// Hits per rule id.
  final Map<String, int> hits = {};

  /// Every lesson received, in order.
  final List<RuleLesson> lessons = [];

  @override
  List<ParserRule> get current => List.unmodifiable(_rules.values);

  @override
  Stream<List<ParserRule>> watch() => _changes.stream;

  @override
  Future<void> learn(RuleLesson lesson) async {
    lessons.add(lesson);
    if (lesson.isEmpty || rulePattern(lesson.pattern).isEmpty) return;
    final id = ruleIdFor(lesson.kind, lesson.pattern);
    _rules[id] = mergeLesson(_rules[id], lesson);
    hits[id] = (hits[id] ?? 0) + 1;
    if (!_changes.isClosed) _changes.add(current);
  }

  /// Closes [watch].
  Future<void> dispose() => _changes.close();
}
