/// Step 7 of the fast parser: learned rules (AI_PIPELINE 5, DATA_MODEL
/// 2.12).
library;

import 'package:meta/meta.dart';
import 'package:xpense_shared/parse/normalize.dart';
import 'package:xpense_shared/parse/tokens.dart';
import 'package:xpense_shared/schema/parse_result.dart';

/// Confidence of a field set by a learned rule (AI_PIPELINE 5).
const double ruleHitConfidence = 0.99;

/// What a rule's pattern matches (DATA_MODEL 2.12 `kind`).
///
/// The order is the precedence when two rules set the same field: a
/// merchant is the most specific evidence, a keyword the least.
enum RuleKind {
  /// A merchant name (`costco`).
  merchant('merchant'),

  /// A person's name (`alex`).
  person('person'),

  /// Any keyword (`generator`).
  keyword('keyword');

  new(this.wire);

  /// The stored value.
  final String wire;
}

/// A field a rule sets; [wire] is the `RuleHit.field` value.
enum RuleField {
  /// The category id.
  categoryId('categoryId'),

  /// The account id.
  accountId('accountId'),

  /// Whose money it is (`me`, `partner`, `joint`).
  who('who'),

  /// The intent wire value.
  intent('intent');

  new(this.wire);

  /// The schema value.
  final String wire;
}

/// A learned rule from the local cache, as the parser needs it.
///
/// The stored document (DATA_MODEL 2.12) keeps `sets` as `{categoryId?,
/// accountId?, whoScope?, whoUid?, type?}`; the rules repository maps it to
/// these four fields (`whoScope`/`whoUid` to [who] relative to the reading
/// member, `type` to [intent]).
@immutable
final class ParserRule {
  /// Creates a rule. [pattern] is normalised when matched.
  const new({
    required this.id,
    required this.kind,
    required this.pattern,
    this.categoryId,
    this.accountId,
    this.who,
    this.intent,
  });

  /// The rule id.
  final String id;

  /// What the pattern matches.
  final RuleKind kind;

  /// The pattern, matched as whole words in the normalised text.
  final String pattern;

  /// The category the rule sets.
  final String? categoryId;

  /// The account the rule sets.
  final String? accountId;

  /// The `who` value the rule sets.
  final String? who;

  /// The intent wire value the rule sets.
  final String? intent;

  /// The fields this rule sets, in [RuleField] order.
  Map<RuleField, String> get sets => {
    RuleField.categoryId: ?categoryId,
    RuleField.accountId: ?accountId,
    RuleField.who: ?who,
    RuleField.intent: ?intent,
  };
}

/// One field set by a matched rule.
@immutable
final class AppliedRule {
  /// Creates an applied rule.
  const new({
    required this.ruleId,
    required this.field,
    required this.value,
    required this.start,
    required this.end,
  });

  /// The rule id.
  final String ruleId;

  /// The field set.
  final RuleField field;

  /// The value set.
  final String value;

  /// Start offset of the match in the normalised text.
  final int start;

  /// End offset (exclusive) of the match.
  final int end;

  /// The schema form, with confidence [ruleHitConfidence].
  RuleHit toSchema() => RuleHit(
    ruleId: ruleId,
    field: field.wire,
    value: value,
    confidence: ruleHitConfidence,
  );

  @override
  bool operator ==(Object other) =>
      other is AppliedRule &&
      other.ruleId == ruleId &&
      other.field == field &&
      other.value == value &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(ruleId, field, value, start, end);

  @override
  String toString() => 'AppliedRule($ruleId ${field.wire}=$value)';
}

/// Applies [rules] to normalised [text] and returns at most one winner per
/// field, in [RuleField] order.
///
/// A rule matches when its normalised pattern occurs as whole words. When
/// several matching rules set the same field, the winner is chosen by
/// [RuleKind] precedence (merchant, person, keyword), then the longer
/// pattern, then the earlier match, then the smaller rule id, so the result
/// never depends on the order of [rules]. Rules with an empty pattern never
/// match.
List<AppliedRule> applyRules(String text, List<ParserRule> rules) {
  final best = <RuleField, (ParserRule, int, int)>{};
  for (final rule in rules) {
    final pattern = normalizeText(rule.pattern);
    final starts = findWholeWord(text, pattern);
    if (starts.isEmpty) continue;
    final at = starts.first;
    final end = at + pattern.length;
    for (final field in rule.sets.keys) {
      final current = best[field];
      if (current == null || _beats(rule, pattern, at, current)) {
        best[field] = (rule, at, end);
      }
    }
  }
  return [
    for (final field in RuleField.values)
      if (best[field] case (final rule, final at, final end))
        AppliedRule(
          ruleId: rule.id,
          field: field,
          value: rule.sets[field]!,
          start: at,
          end: end,
        ),
  ];
}

bool _beats(
  ParserRule rule,
  String pattern,
  int at,
  (ParserRule, int, int) current,
) {
  final (other, otherAt, otherEnd) = current;
  if (rule.kind != other.kind) return rule.kind.index < other.kind.index;
  final length = pattern.length;
  final otherLength = otherEnd - otherAt;
  if (length != otherLength) return length > otherLength;
  if (at != otherAt) return at < otherAt;
  return rule.id.compareTo(other.id) < 0;
}
