/// The real [EntryClassifier]: the household's question set, one Decisions
/// API call per message, and the fallback chain (AI_PIPELINE 7, WP-S4).
///
/// 1. Decisions API. One retry with jitter on 429, 5xx or no response. A key
///    error re-reads the key once (inside [DecisionsApi]).
/// 2. A safety block (HTTP 400 with a safety `error.code`, or 200 with
///    `prompt_feedback.block_reason`) skips everything: `{unavailable}`.
/// 3. Anything else that did not answer (an `invalid_request`, which is a
///    proxy bug; a refused key; a retry that failed too) goes to the
///    Flash-Lite fallback, marked `calibrated: false`.
/// 4. When the fallback cannot answer either: `{unavailable: true}`.
///
/// Logs carry ids, question keys, counts and codes, never the message, a
/// name or the key.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:logging/logging.dart';
import 'package:xpense_agent/admin/admin_gateway.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/config/runtime_config.dart';
import 'package:xpense_agent/decide/answers.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/decide/decide_cache.dart';
import 'package:xpense_agent/decide/decisions_api.dart';
import 'package:xpense_agent/decide/duplicates.dart';
import 'package:xpense_agent/decide/fallback.dart';
import 'package:xpense_agent/decide/household_profile.dart';
import 'package:xpense_agent/decide/local_day.dart';
import 'package:xpense_agent/decide/question_set.dart';
import 'package:xpense_agent/telemetry/usage_counters.dart';
import 'package:xpense_shared/xpense_shared.dart';

final _log = Logger('xpense.decide');

/// Estimated cost in millionths of a US dollar, from the paid-tier prices
/// read on 2026-11-22 (WP-S4): `gemini-decision-1` USD 0.10 per 1M input
/// tokens, output not billed.
int decisionsCostMicros(int inputTokens) => (inputTokens + 9) ~/ 10;

/// `gemini-3.5-flash-lite`: USD 0.30 per 1M input, 2.50 per 1M output.
int fallbackCostMicros(int inputTokens, int outputTokens) =>
    (inputTokens * 3 + outputTokens * 25 + 9) ~/ 10;

/// The Decisions-backed classifier.
final class DecisionsClassifier implements EntryClassifier {
  /// Creates the classifier.
  new({
    required this._api,
    required this._households,
    required this._config,
    required this._usage,
    this._fallback = const NoFallback(),
    DecideCache? cache,
    Clock? clock,
    Random? random,
    Future<void> Function(Duration)? sleep,
    this._usdIqdOn,
  }) : _cache = cache ?? DecideCache(clock: clock),
       _clock = clock ?? const Clock(),
       _random = random ?? Random(),
       _sleep = sleep ?? Future<void>.delayed;

  final DecisionsApi _api;
  final HouseholdSource _households;
  final RuntimeConfigLoader _config;
  final UsageCounters _usage;
  final FallbackClassifier _fallback;
  final DecideCache _cache;
  final Clock _clock;
  final Random _random;
  final Future<void> Function(Duration) _sleep;

  /// IQD per USD for a household on a day (`YYYY-MM-DD`): that day's rate
  /// or the latest before it, null when it has none. Without it the
  /// duplicate search looks in the message's currency only.
  final Future<String?> Function(String hid, String day)? _usdIqdOn;

  static final _unavailable = DecideResponse(unavailable: true);

  @override
  Future<DecideResponse> classify({
    required XpenseContext context,
    required String text,
    required Set<DecideQuestion> ask,
    DecideParsed? parsed,
    List<ParseHint> hints = const [],
    List<DuplicateCandidate> candidates = const [],
    String lang = 'en',
  }) async {
    final config = await _config.current();
    if (!config.isOn('decideEnabled')) {
      _log.info({'message': 'decide: switched off', 'hid': context.hid});
      return _unavailable;
    }
    if (ask.isEmpty) return DecideResponse(calibrated: true);

    final HouseholdProfile profile;
    try {
      profile = await _households.profile(hid: context.hid, uid: context.uid);
    } on GatewayUnavailable catch (e) {
      _log.warning({
        'message': 'decide: household unreadable',
        'op': e.operation,
      });
      return _unavailable;
    }

    final now = localDay(context.tz, _clock.now());
    if (!now.known) {
      _log.warning({'message': 'decide: unknown time zone', 'tz': context.tz});
    }
    final (found, alsoAs) = ask.contains(DecideQuestion.duplicate)
        ? await _candidates(context, profile, now.day, parsed, hints)
        : (const <DuplicateCandidate>[], null);

    final plan = buildPlan(
      profile: profile,
      speakerUid: context.uid,
      today: now.day,
      text: text,
      ask: ask,
      parsed: parsed,
      candidates: found,
      alsoAs: alsoAs,
    );
    if (plan.questions.isEmpty) {
      return DecideResponse(calibrated: true);
    }

    final body = plan.body(config.model('decide'));
    // The body describes candidates without their ids, and the response's
    // `duplicate_of` is an id, so the ids are part of the key: an entry
    // deleted and saved again with the same description is a miss.
    final cacheKey = DecideCache.keyFor(
      hid: context.hid,
      uid: context.uid,
      body: _canonical(body),
      candidateIds: [for (final c in found) c.txnId],
    );
    if (_cache.get(cacheKey) case final cached?) {
      return cached;
    }

    var outcome = await _api.send(body);
    if (outcome is DecisionTransient) {
      _log.info({'message': 'decide: retrying', 'detail': outcome.detail});
      await _sleep(Duration(milliseconds: 100 + _random.nextInt(300)));
      outcome = await _api.send(body);
    }

    final fields = {
      'hid': context.hid,
      'asked': [for (final q in plan.asked) q.key],
      'status': outcome.status,
    };
    switch (outcome) {
      case DecisionAnswered(:final answers, :final inputTokens):
        final response = mapAnswers(
          plan,
          answers,
          calibrated: true,
          duplicateOf: found.firstOrNull?.txnId,
        );
        _cache.put(cacheKey, response);
        await _count(context.hid, {
          UsageCounter.decisions: 1,
          UsageCounter.inputTokens: inputTokens,
          UsageCounter.costMicrosUsd: decisionsCostMicros(inputTokens),
        });
        _log.info({
          ...fields,
          'message': 'decide: answered',
          'inputTokens': inputTokens,
          'answered': [for (final q in answeredIn(response)) q.key],
        });
        return response;
      case DecisionBlocked(:final reason):
        // The message itself was refused; another model would be asked the
        // same thing, so the phone classifies on its own.
        await _count(context.hid, {UsageCounter.decisions: 1});
        _log.info({...fields, 'message': 'decide: blocked', 'reason': reason});
        return _unavailable;
      case DecisionRequestRejected(:final code, :final message):
        // Our request broke a rule (a key, a count, a field): a bug here,
        // not in the user's message.
        _log.severe({
          ...fields,
          'message': 'decide: request rejected',
          'code': code,
          'detail': ?message,
        });
      case DecisionKeyRejected(:final statusText):
        _log.shout({
          ...fields,
          'message': 'decide: API key rejected; check GEMINI_API_KEY',
          'errorStatus': ?statusText,
        });
      case DecisionTransient(:final detail):
        _log.warning({
          ...fields,
          'message': 'decide: unavailable',
          'detail': detail,
        });
      case DecisionUnexpected(:final detail):
        _log.severe({
          ...fields,
          'message': 'decide: unexpected',
          'detail': detail,
        });
    }
    return await _runFallback(context, plan, config, found);
  }

  Future<DecideResponse> _runFallback(
    XpenseContext context,
    DecideRequestPlan plan,
    RuntimeConfig config,
    List<DuplicateCandidate> found,
  ) async {
    final result = await _fallback.answer(
      plan,
      model: config.model('decideFallback'),
    );
    if (result == null) return _unavailable;
    await _count(context.hid, {
      UsageCounter.decisions: 1,
      UsageCounter.inputTokens: result.inputTokens,
      UsageCounter.outputTokens: result.outputTokens,
      UsageCounter.costMicrosUsd: fallbackCostMicros(
        result.inputTokens,
        result.outputTokens,
      ),
    });
    final response = mapAnswers(
      plan,
      result.answers,
      calibrated: false,
      duplicateOf: found.firstOrNull?.txnId,
    );
    _log.info({
      'message': 'decide: fallback answered',
      'hid': context.hid,
      'answered': [for (final q in answeredIn(response)) q.key],
    });
    return response;
  }

  /// The duplicate candidates, and the converted amount when one of them
  /// was found in the other currency (the model is told both figures).
  Future<(List<DuplicateCandidate>, SameAmount?)> _candidates(
    XpenseContext context,
    HouseholdProfile profile,
    LocalDay today,
    DecideParsed? parsed,
    List<ParseHint> hints,
  ) async {
    final amount = parsed?.amountMinor;
    final currency = parsed?.currency;
    if (amount == null || currency == null) {
      return (const <DuplicateCandidate>[], null);
    }
    final day = parseDay(parsed?.date) ?? today;
    final accountId = [
      for (final h in hints)
        if (h.kind == 'account' && h.id != null) h.id!,
    ].firstOrNull;
    final alsoAs = await _converted(
      context,
      amount,
      currency,
      day,
      accountCurrency: accountId == null
          ? null
          : profile.account(accountId)?.currency,
    );
    final entries = <RecentEntry>[];
    try {
      final window = candidateWindow(day);
      for (final minor in {amount, ?alsoAs?.amountMinor}) {
        entries.addAll(
          await _households.entriesWithAmount(
            hid: context.hid,
            uid: context.uid,
            amountMinor: minor,
            fromDay: window.from,
            toDay: window.to,
          ),
        );
      }
    } on GatewayUnavailable catch (e) {
      // No candidates: `duplicate` is not asked.
      _log.warning({
        'message': 'decide: duplicate search failed',
        'op': e.operation,
      });
    }
    final found = selectCandidates(
      entries: entries,
      profile: profile,
      amountMinor: amount,
      currency: currency,
      day: day,
      accountId: accountId,
      alsoAs: alsoAs,
    );
    return (
      found,
      found.any((c) => c.currency == alsoAs?.currency) ? alsoAs : null,
    );
  }

  /// [amountMinor] of [code] in the household's other currency at [day]'s
  /// rate: what an entry paid from an account in that currency was saved
  /// as (DATA_MODEL 1). Null when the account named is in [code] itself,
  /// or there is no rate.
  Future<SameAmount?> _converted(
    XpenseContext context,
    int amountMinor,
    String code,
    LocalDay day, {
    String? accountCurrency,
  }) async {
    final lookup = _usdIqdOn;
    final (from, to) = switch (code) {
      'USD' => (Currency.usd, Currency.iqd),
      'IQD' => (Currency.iqd, Currency.usd),
      _ => (null, null),
    };
    if (lookup == null || from == null || to == null) return null;
    if (accountCurrency != null && accountCurrency != to.code) return null;
    final String? usdIqd;
    try {
      usdIqd = await lookup(context.hid, isoDay(day));
    } on Object catch (e) {
      _log.warning({'message': 'decide: rate unreadable', 'error': '$e'});
      return null;
    }
    if (usdIqd == null) return null;
    final rate = FxRate.parse('USD/IQD', usdIqd).valueOrNull;
    final converted = rate?.convert(Money(amountMinor, from), to).valueOrNull;
    if (converted == null || converted.minorUnits < 1) return null;
    return (amountMinor: converted.minorUnits, currency: to.code);
  }

  Future<void> _count(String hid, Map<UsageCounter, int> amounts) async {
    try {
      await _usage.add(hid, amounts);
    } on GatewayUnavailable catch (e) {
      // The answer is still good; the counter is best effort.
      _log.warning({'message': 'decide: usage not counted', 'op': e.operation});
    }
  }

  /// A stable string for the cache key (map order is insertion order, which
  /// the plan builds deterministically).
  static String _canonical(Map<String, Object?> body) => jsonEncode(body);
}
