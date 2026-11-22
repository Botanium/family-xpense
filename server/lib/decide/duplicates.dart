/// Deterministic duplicate candidates (AI_PIPELINE 7): same amount and
/// currency, same account when the account is known, dated within one day
/// of the message. The model judges `duplicate` only when this finds one.
library;

import 'package:xpense_agent/decide/household_profile.dart';
import 'package:xpense_agent/decide/question_set.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// The most candidates listed in the shared input.
const int maxCandidates = 5;

/// The window searched: the message's date plus and minus one day.
({String from, String to}) candidateWindow(LocalDay day) =>
    (from: isoDay(addDays(day, -1)), to: isoDay(addDays(day, 1)));

/// Whether [c] matches the message under the deterministic rule.
bool isCandidate(
  DuplicateCandidate c, {
  required int amountMinor,
  required String currency,
  required LocalDay day,
  String? accountId,
  String? candidateAccountId,
}) {
  if (c.amountMinor != amountMinor || c.currency != currency) return false;
  if (accountId != null &&
      candidateAccountId != null &&
      accountId != candidateAccountId) {
    return false;
  }
  final on = parseDay(c.occurredOn);
  if (on == null) return false;
  final w = candidateWindow(day);
  final iso = isoDay(on);
  return iso.compareTo(w.from) >= 0 && iso.compareTo(w.to) <= 0;
}

/// The candidates for one message: the household's matching entries
/// (titled with the account name) merged with [fromCaller] that pass the
/// same rule, without repeats, nearest date first, at most [maxCandidates].
List<DuplicateCandidate> selectCandidates({
  required List<RecentEntry> entries,
  required List<DuplicateCandidate> fromCaller,
  required HouseholdProfile profile,
  required int amountMinor,
  required String currency,
  required LocalDay day,
  String? accountId,
}) {
  final out = <String, DuplicateCandidate>{};
  for (final e in entries) {
    if (e.deleted) continue;
    final title = [
      if (e.title case final t? when t.isNotEmpty) t,
      if (profile.account(e.accountId) case final a?) a.name,
    ].join(', ');
    final c = DuplicateCandidate(
      txnId: e.id,
      amountMinor: e.amountMinor,
      currency: e.currency,
      occurredOn: e.occurredOn,
      title: title.isEmpty ? null : title,
    );
    if (isCandidate(
      c,
      amountMinor: amountMinor,
      currency: currency,
      day: day,
      accountId: accountId,
      candidateAccountId: e.accountId,
    )) {
      out[e.id] = c;
    }
  }
  for (final c in fromCaller) {
    if (out.containsKey(c.txnId)) continue;
    if (isCandidate(
      c,
      amountMinor: amountMinor,
      currency: currency,
      day: day,
    )) {
      out[c.txnId] = c;
    }
  }
  int distance(DuplicateCandidate c) {
    final on = parseDay(c.occurredOn)!;
    return DateTime.utc(
      on.year,
      on.month,
      on.day,
    ).difference(DateTime.utc(day.year, day.month, day.day)).inDays.abs();
  }

  final sorted = out.values.toList()
    ..sort((a, b) {
      final byDistance = distance(a).compareTo(distance(b));
      return byDistance != 0 ? byDistance : a.txnId.compareTo(b.txnId);
    });
  return sorted.take(maxCandidates).toList();
}
