/// Receipt grouping for `ReceiptSummary` (A2UI_CATALOG 3.2).
///
/// The "Split by category" switch regroups a receipt's lines on the phone.
/// Line items rarely add up to the total (tax, service, rounding,
/// discounts), so the total is divided across the groups with [allocate],
/// weighted by each group's line sum: the groups always add up to the
/// receipt total, to the minor unit.
library;

import 'package:meta/meta.dart';
import 'package:xpense_shared/money/allocate.dart';
import 'package:xpense_shared/surface/surface_builder.dart';

/// One group of a receipt: a category (or none) and its share of the total.
@immutable
final class ReceiptGroup {
  /// Creates a group.
  const new({
    required this.categoryId,
    required this.lineCount,
    required this.amountMinor,
  });

  /// The category, or null for lines with none.
  final String? categoryId;

  /// How many lines fell into the group.
  final int lineCount;

  /// The group's share of the receipt total, in minor units.
  final int amountMinor;

  @override
  bool operator ==(Object other) =>
      other is ReceiptGroup &&
      other.categoryId == categoryId &&
      other.lineCount == lineCount &&
      other.amountMinor == amountMinor;

  @override
  int get hashCode => Object.hash(categoryId, lineCount, amountMinor);

  @override
  String toString() => 'ReceiptGroup($categoryId, $lineCount, $amountMinor)';
}

/// Reads a receipt from the data model, or returns null when its shape is
/// wrong.
SurfaceReceipt? receiptFromJson(Object? json) {
  if (json is! Map) return null;
  final merchant = json['merchant'];
  final occurredOn = json['occurredOn'];
  final currency = json['currency'];
  final total = json['totalMinor'];
  final time = json['occurredTime'];
  if (merchant is! String ||
      occurredOn is! String ||
      currency is! String ||
      total is! num ||
      total != total.truncate() ||
      (time != null && time is! String)) {
    return null;
  }
  final lines = <SurfaceReceiptLine>[];
  for (final line in json['lines'] as List? ?? const []) {
    if (line is! Map) return null;
    final text = line['text'];
    final amount = line['amountMinor'];
    final category = line['categoryId'];
    if (text is! String ||
        amount is! num ||
        amount != amount.truncate() ||
        (category != null && category is! String)) {
      return null;
    }
    lines.add(
      SurfaceReceiptLine(
        text: text,
        amountMinor: amount.toInt(),
        categoryId: category as String?,
      ),
    );
  }
  return SurfaceReceipt(
    merchant: merchant,
    occurredOn: occurredOn,
    occurredTime: time as String?,
    currency: currency,
    totalMinor: total.toInt(),
    lines: lines,
  );
}

/// The groups of [receipt]: one per category in order of first appearance
/// when [split], otherwise one group holding the whole total.
List<ReceiptGroup> groupReceipt(SurfaceReceipt receipt, {required bool split}) {
  final total = receipt.totalMinor;
  if (!split || receipt.lines.isEmpty) {
    return [
      ReceiptGroup(
        categoryId: _mainCategory(receipt),
        lineCount: receipt.lines.length,
        amountMinor: total,
      ),
    ];
  }
  final sums = <String?, int>{};
  final counts = <String?, int>{};
  for (final line in receipt.lines) {
    sums[line.categoryId] = (sums[line.categoryId] ?? 0) + line.amountMinor;
    counts[line.categoryId] = (counts[line.categoryId] ?? 0) + 1;
  }
  final keys = sums.keys.toList();
  final shares = allocate(total, [for (final k in keys) sums[k]!]);
  return [
    for (final (i, key) in keys.indexed)
      ReceiptGroup(
        categoryId: key,
        lineCount: counts[key]!,
        amountMinor: shares[i],
      ),
  ];
}

/// The drafts for [groups]: copies of the first of [drafts] with each
/// group's amount and category. Ids are `<base>_<n>` when there is more
/// than one group, otherwise `<base>`.
///
/// The converted amount (`fx.baseAmountMinor`) depends on the amount, so it
/// is never copied: the receipt's converted total (see [convertedTotal]) is
/// divided across the groups with [allocate], in proportion to their
/// amounts, so the groups' converted amounts also add up exactly. When any
/// draft has no converted amount, the copies have none either, and the
/// write path converts them.
List<Map<String, Object?>> draftsForGroups(
  List<Map<String, Object?>> drafts,
  List<ReceiptGroup> groups,
) {
  if (drafts.isEmpty) return const [];
  final template = drafts.first;
  final base = '${template['id']}'.replaceFirst(RegExp(r'_\d+$'), '');
  final converted = convertedTotal(drafts);
  final shares = converted == null
      ? null
      : allocate(converted, [for (final g in groups) g.amountMinor]);
  return [
    for (final (i, group) in groups.indexed)
      _groupDraft(
        template,
        id: groups.length == 1 ? base : '${base}_${i + 1}',
        group: group,
        baseAmountMinor: shares?[i],
      ),
  ];
}

/// The sum of every draft's converted amount (`fx.baseAmountMinor`), or
/// null when a draft has none.
int? convertedTotal(List<Object?> drafts) {
  if (drafts.isEmpty) return null;
  var total = 0;
  for (final draft in drafts) {
    final amount = switch (draft) {
      {'fx': {'baseAmountMinor': final num n}} when n == n.truncate() =>
        n.toInt(),
      _ => null,
    };
    if (amount == null) return null;
    total += amount;
  }
  return total;
}

Map<String, Object?> _groupDraft(
  Map<String, Object?> template, {
  required String id,
  required ReceiptGroup group,
  required int? baseAmountMinor,
}) {
  final draft = {
    ...template,
    'id': id,
    'amountMinor': group.amountMinor,
    'categoryId': group.categoryId ?? template['categoryId'],
  };
  if (template['fx'] case final Map<Object?, Object?> fx) {
    draft['fx'] = {
      for (final MapEntry(:key, :value) in fx.entries)
        if (key != 'baseAmountMinor') '$key': value,
      'baseAmountMinor': ?baseAmountMinor,
    };
  }
  // A group with a category answers a missing category.
  final missing = [
    for (final field in template['missing'] as List? ?? const [])
      if (field != 'categoryId' || group.categoryId == null) field,
  ];
  if (missing.isEmpty) {
    draft.remove('missing');
  } else {
    draft['missing'] = missing;
  }
  return draft;
}

/// The category with the largest line sum, so an unsplit receipt keeps the
/// category most of it belongs to.
String? _mainCategory(SurfaceReceipt receipt) {
  final sums = <String?, int>{};
  for (final line in receipt.lines) {
    sums[line.categoryId] = (sums[line.categoryId] ?? 0) + line.amountMinor;
  }
  String? best;
  var bestSum = -1;
  for (final MapEntry(:key, :value) in sums.entries) {
    if (key != null && value > bestSum) {
      best = key;
      bestSum = value;
    }
  }
  return best;
}
