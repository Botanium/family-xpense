/// `prepareEntries`: the model's proposed entries become checked drafts
/// (AI_PIPELINE 8 and 9).
///
/// The model proposes what it read; this function decides what is true:
/// - an amount is kept only when the fast parser found the same figure in
///   the user's messages ("never invent amounts", AI_PIPELINE 10);
/// - account, category and person words are resolved against the member's
///   own household data;
/// - whatever the words leave open is classified through [EntryClassifier]
///   (one call per entry, all its uncertain fields at once), and the
///   confidence policy decides prefill, "Guessed" badge or follow-up;
/// - FX, duplicate candidates and recurring hints are added.
///
/// Idempotent: each call returns the whole draft set for the turn, with ids
/// `d1…dn`, so a second call replaces the first (parallel tool calls cannot
/// race on incremental state).
library;

import 'package:decimal/decimal.dart';
import 'package:logging/logging.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/tools/household_reader.dart';
import 'package:xpense_agent/tools/household_snapshot.dart';
import 'package:xpense_agent/tools/local_day.dart';
import 'package:xpense_agent/tools/schemas.dart';
import 'package:xpense_agent/tools/tool_deps.dart';
import 'package:xpense_shared/xpense_shared.dart';

final _log = Logger('xpense.tools.prepareEntries');

/// The Decisions catch-all option key (`decide/question_set.dart`).
const unspecifiedChoice = 'unspecified';

/// The order follow-ups are asked in (AI_PIPELINE 9).
const followUpOrder = [
  'intent',
  'amountMinor',
  'currency',
  'accountId',
  'toAccountId',
  'categoryId',
  'personName',
  'occurredOn',
];

/// Runs `prepareEntries` for the member in [context].
Future<PrepareEntriesOutput> prepareEntries(
  PrepareEntriesInput input,
  XpenseContext context,
  ToolDeps deps,
) async {
  final snap = await deps.snapshots.get(context.hid, context.uid);
  if (snap == null) {
    return PrepareEntriesOutput(drafts: [], notes: ['household_not_found']);
  }
  final thresholds = await deps.thresholds();
  final notes = <String>[];
  var entries = input.entries ?? const <ProposedEntry>[];
  if (entries.length > maxDraftsPerSurface) {
    notes.add('only the first $maxDraftsPerSurface entries were kept');
    entries = entries.sublist(0, maxDraftsPerSurface);
  }

  final clock = localClock(deps.clock, context.tz);
  final today = localToday(deps.clock, context.tz);
  final parseContext = ParseContext(
    clock: clock,
    accounts: snap.parserAccounts,
    people: snap.parserPeople,
    categories: snap.parserCategories,
  );
  // Every amount the user actually wrote, across the conversation's user
  // messages (a follow-up may correct an amount from an earlier turn).
  // Parsed without the household: a named account makes the parser read
  // the message's other bare amounts in its currency ("12.50" after "cash
  // wallet" becomes 12,500 IQD), and here only the figures matter.
  final plain = ParseContext(clock: clock);
  final texts = deps.turnText();
  final pool = _AmountPool([
    for (final text in texts) ...parseText(text, plain).amounts,
  ]);

  final builders = [
    for (final (i, e) in entries.indexed)
      _DraftBuilder(
        id: 'd${i + 1}',
        entry: e,
        text: _memberText(e.text, texts),
        snap: snap,
        today: today.iso,
        parseContext: parseContext,
      ),
  ];
  for (final b in builders) {
    b
      ..resolveAmount(pool, notes)
      ..resolveWords();
  }
  // Duplicate candidates and FX need the ledger; classification needs the
  // classifier. Run each entry's work concurrently.
  await Future.wait([
    for (final b in builders)
      b.finish(context: context, deps: deps, thresholds: thresholds),
  ]);

  final drafts = [for (final b in builders) b.build()];
  return PrepareEntriesOutput(
    drafts: drafts,
    ask: _firstFollowUp(drafts, builders),
    notes: notes.isEmpty ? null : notes,
  );
}

/// The entry's words, used by every "did the member write it" check: the
/// model's `text` when it is a verbatim span of a member message, otherwise
/// the latest member message itself (a paraphrase could carry words the
/// member never wrote).
String _memberText(String? span, List<String> texts) {
  if (span != null && span.trim().isNotEmpty) {
    final s = _norm(span);
    for (final t in texts) {
      if (' ${_norm(t)} '.contains(' $s ')) return span;
    }
  }
  return texts.isEmpty ? '' : texts.last;
}

/// The amounts found in the messages; each can back one entry.
final class _AmountPool {
  new(this._amounts);

  final List<ResolvedAmount> _amounts;
  final _used = <int>{};

  /// The first unused amount equal to [value], preferring one whose
  /// currency agrees with [currency].
  ResolvedAmount? take(Decimal value, String? currency) {
    int? pick;
    for (final (i, a) in _amounts.indexed) {
      if (_used.contains(i) || a.value != value) continue;
      if (currency == null ||
          a.currency == null ||
          a.currency!.code == currency) {
        pick = i;
        break;
      }
      pick ??= i;
    }
    if (pick == null) {
      // An amount already used by another entry may be repeated ("two
      // coffees, 4 each").
      for (final a in _amounts) {
        if (a.value == value) return a;
      }
      return null;
    }
    _used.add(pick);
    return _amounts[pick];
  }
}

/// Parses a decimal the way users write amounts ("1,400", "12.50").
Decimal? parseWrittenAmount(String? s) {
  if (s == null) return null;
  final cleaned = s.replaceAll(RegExp(r'[,\s]'), '');
  if (!RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(cleaned)) return null;
  return Decimal.tryParse(cleaned);
}

final class _DraftBuilder {
  new({
    required this.id,
    required this.entry,
    required this.text,
    required this.snap,
    required this.today,
    required this.parseContext,
  }) : intent =
           CaptureIntent.tryParse(entry.intent ?? '') ?? CaptureIntent.expense;

  final String id;
  final ProposedEntry entry;

  /// The entry's words, or the message when the model gave none.
  final String text;
  final HouseholdSnapshot snap;
  final String today;
  final ParseContext parseContext;
  final CaptureIntent intent;

  int? amountMinor;
  String? currency;
  String? accountId;
  String? toAccountId;
  String? categoryId;
  String? who;
  String? personId;
  String? occurredOn;
  final confidence = <String, double>{};
  final guessed = <String>{};
  final listedMissing = <String>{};
  HouseholdCategory? modelCategory;

  /// The amount as written (major units), kept to re-read it in another
  /// currency.
  Decimal? amountValue;

  /// Whether a currency word or an account the member named settled the
  /// currency.
  bool currencyFromWords = false;
  HouseholdAccount? modelAccount;
  HouseholdAccount? modelToAccount;

  /// Account ids by the classifier's probability, highest first.
  List<String> accountRanking = const [];

  /// Whether the classifier answered the category question (any answer,
  /// low or `unspecified` included).
  bool categoryScored = false;

  /// The same for the account questions.
  bool accountScored = false;
  bool toAccountScored = false;
  FxQuote? fx;
  DuplicateHint? duplicate;
  RecurringHint? recurring;

  bool get _isTransfer =>
      intent == CaptureIntent.transfer || intent == CaptureIntent.savingsMove;

  bool get _hasCategory =>
      intent == CaptureIntent.expense || intent == CaptureIntent.income;

  bool get _hasPerson => switch (intent) {
    CaptureIntent.loanGiven ||
    CaptureIntent.loanTaken ||
    CaptureIntent.repaymentReceived ||
    CaptureIntent.repaymentMade => true,
    _ => false,
  };

  void resolveAmount(_AmountPool pool, List<String> notes) {
    final value = parseWrittenAmount(entry.amount);
    if (value == null) {
      if (entry.amount != null) notes.add('$id: unreadable amount');
      return;
    }
    final found = pool.take(value, entry.currency);
    if (found == null) {
      // The model's figure is not in anything the user wrote: drop it and
      // ask (AI_PIPELINE 10).
      notes.add(
        '$id: amount ${entry.amount} is not in the message; ask for it',
      );
      _log.info('dropped an amount not found in the message');
      return;
    }
    amountValue = found.value;
    // Currency, most reliable first: a currency word next to or about the
    // amount; an account the member named; the model's reading; the
    // household base currency. Only the first two are not guesses: an
    // account the model hinted but the member did not write settles
    // nothing (its currency can still follow it later, as a guess).
    final hint = entry.accountHint;
    final named = hint != null && _wrote(hint)
        ? _matchAccounts(hint, null)
        : const <HouseholdAccount>[];
    final String code;
    if (found.source == CurrencySource.word && found.currency != null) {
      code = found.currency!.code;
      currencyFromWords = true;
    } else if (named.length == 1) {
      code = named.single.currency;
      currencyFromWords = true;
    } else {
      code = entry.currency ?? snap.baseCurrency;
      guessed.add('currency');
    }
    final known = Currency.tryParse(code);
    if (known == null) {
      // Household data with a currency the app does not know: ask.
      notes.add('$id: unknown currency $code; ask for the amount');
      guessed.remove('currency');
      return;
    }
    currency = code;
    final money = Money.parseMajor(found.value.toString(), known);
    if (money case Ok(:final value)) {
      amountMinor = value.minorUnits;
    } else {
      notes.add('$id: $code cannot hold the amount ${entry.amount}');
    }
  }

  /// Moves a guessed currency to [account]'s, re-reading the written amount
  /// in it. Returns false (and changes nothing) when the currency was
  /// written or named, or the amount does not fit the account's currency.
  bool _followAccountCurrency(HouseholdAccount account) {
    if (account.currency == currency) return true;
    if (currencyFromWords) return false;
    final to = Currency.tryParse(account.currency);
    final value = amountValue;
    if (to == null) return false;
    if (value != null) {
      final money = Money.parseMajor(value.toString(), to);
      if (money case Ok(:final value)) {
        amountMinor = value.minorUnits;
      } else {
        return false;
      }
    }
    currency = account.currency;
    guessed.add('currency');
    return true;
  }

  void resolveWords() {
    // Account words. Like categories below, only words the member wrote
    // settle a field; a hint the model made up ("dollars", "checking" for
    // "Groceries 45") is kept as a guess the classifier can override.
    final hint = entry.accountHint;
    if (hint != null && _wrote(hint)) {
      final accounts = _matchAccounts(hint, currency);
      if (accounts.length == 1) {
        accountId = accounts.single.id;
        confidence['account'] = 1;
      }
    } else {
      // Its currency need not match a guessed currency: the two are
      // reconciled once the classifier has answered.
      final accounts = _matchAccounts(hint, null);
      if (accounts.length == 1) modelAccount = accounts.single;
    }
    if (_isTransfer) {
      final to = _matchAccounts(entry.toAccountHint, null);
      if (to.length == 1 && to.single.id != accountId) {
        if (_wrote(entry.toAccountHint!)) {
          toAccountId = to.single.id;
        } else {
          modelToAccount = to.single;
        }
      }
    }
    // Category words. Only words the member wrote settle the category; a
    // slug the model picked (say "lunch" → `bakery_tea`) is its reading, kept
    // as a guess unless the classifier answers.
    if (_hasCategory) {
      final c = _matchCategory(entry.categoryHint);
      if (c != null) {
        if (_mentions(text, entry.categoryHint!) || _mentions(text, c.name)) {
          categoryId = c.id;
          confidence['category'] = 1;
        } else {
          modelCategory = c;
        }
      }
    }
    // Who: only when the words say so ("we", "my", the partner's name).
    if (entry.who case final w? when _saysWho(w)) {
      who = w;
      confidence['who'] = 1;
    }
    // Person: only a name the member wrote.
    if (entry.person case final name? when _mentions(text, name)) {
      final p = _matchPerson(name);
      if (p != null) personId = p.id;
    }
    // Date.
    occurredOn = _resolveDate();
  }

  /// Whether the member's words contain every significant word of [hint].
  bool _wrote(String hint) {
    final words = [
      for (final w in _words(_norm(hint)))
        if (w.length > 2 && !_fillerWords.contains(w)) w,
    ];
    final said = _words(_norm(text)).toSet();
    return words.isNotEmpty && words.every(said.contains);
  }

  /// Whether the words carry the cue for [who].
  bool _saysWho(String who) {
    final said = _words(_norm(text)).toSet();
    return switch (who) {
      'joint' => said.any(_jointCues.contains),
      'me' => said.any(_meCues.contains),
      'partner' =>
        said.contains('partner') ||
            _mentions(text, snap.partner?.displayName ?? ''),
      _ => false,
    };
  }

  String _resolveDate() {
    // Date words count only when the member wrote them.
    final dateWords = entry.dateWords;
    for (final words in [
      if (dateWords != null && _mentions(text, dateWords)) dateWords,
      text,
    ]) {
      final mention = parseText(words, parseContext).dateMention;
      if (mention != null) return mention.date.iso;
    }
    return today;
  }

  List<HouseholdAccount> _matchAccounts(String? hint, String? currency) {
    if (hint == null || hint.trim().isEmpty) return const [];
    final h = _norm(hint);
    final byCurrency = [
      for (final a in snap.activeAccounts)
        if (currency == null || a.currency == currency) a,
    ];
    final exact = [
      for (final a in byCurrency)
        if (_norm(a.name) == h) a,
    ];
    if (exact.isNotEmpty) return exact;
    return [
      for (final a in byCurrency)
        if (_norm(a.name).contains(h) ||
            h.contains(_norm(a.name)) ||
            _words(h)
                .any((w) => w.length > 3 && _words(_norm(a.name)).contains(w)))
          a,
    ];
  }

  HouseholdCategory? _matchCategory(String? hint) {
    if (hint == null || hint.trim().isEmpty) return null;
    final kind = intent == CaptureIntent.income ? 'income' : 'expense';
    final h = _norm(hint).replaceAll(' ', '_');
    final candidates = [
      for (final c in snap.activeCategories)
        if (c.kind == kind) c,
    ];
    for (final c in candidates) {
      if (c.slug == h || c.id == hint || _norm(c.name) == _norm(hint)) return c;
    }
    return null;
  }

  HouseholdPerson? _matchPerson(String name) {
    final n = _norm(name);
    for (final p in snap.people) {
      if (_norm(p.name) == n || p.aliases.any((a) => _norm(a) == n)) return p;
    }
    return null;
  }

  Future<void> finish({
    required XpenseContext context,
    required ToolDeps deps,
    required Thresholds thresholds,
  }) async {
    await _classify(context, deps, thresholds);
    // The model's category stands in, as a guess, only when the classifier
    // gave no answer about the category at all. A low or `unspecified`
    // answer keeps the category asked (AI_PIPELINE 9).
    if (categoryId == null && modelCategory != null && !categoryScored) {
      categoryId = modelCategory!.id;
      guessed.add('categoryId');
    }
    // The same for accounts the model named but the member did not.
    if (accountId == null &&
        modelAccount != null &&
        !accountScored &&
        (currency == null || _followAccountCurrency(modelAccount!))) {
      accountId = modelAccount!.id;
      guessed.add('accountId');
    }
    if (_isTransfer &&
        toAccountId == null &&
        modelToAccount != null &&
        !toAccountScored &&
        modelToAccount!.id != accountId) {
      toAccountId = modelToAccount!.id;
      guessed.add('toAccountId');
    }
    await _convert(context, deps);
  }

  Future<void> _classify(
    XpenseContext context,
    ToolDeps deps,
    Thresholds t,
  ) async {
    final ask = <DecideQuestion>{
      DecideQuestion.intent,
      if (accountId == null) DecideQuestion.account,
      if (_isTransfer && toAccountId == null) DecideQuestion.toAccount,
      if (_hasCategory && categoryId == null) DecideQuestion.category,
      if (who == null) DecideQuestion.who,
      if (_hasPerson && personId == null) DecideQuestion.person,
      if (intent == CaptureIntent.expense || intent == CaptureIntent.income)
        DecideQuestion.isRecurring,
      // The classifier finds the duplicate candidates itself (server-side,
      // nearest date first) and asks only when it has some.
      if (amountMinor != null && currency != null) DecideQuestion.duplicate,
    };
    final DecideResponse answer;
    try {
      answer = await deps.classifier.classify(
        context: context,
        text: text,
        ask: ask,
        parsed: DecideParsed(
          amountMinor: amountMinor,
          currency: currency,
          date: occurredOn,
        ),
        // The settled account narrows the classifier's duplicate search.
        hints: [
          if (accountId case final id?)
            ParseHint(kind: 'account', id: id, confidence: 1),
        ],
      );
    } on Object catch (e) {
      // The interface promises no throw for upstream failures; a throw is a
      // bug, but one draft without classification beats a failed turn.
      _log.severe('classifier threw', e);
      return;
    }
    if (answer.unavailable ?? false) return;
    final cap = (answer.calibrated ?? true)
        ? 1.0
        : threshold(t, 'conf_on_device_cap');
    double conf(double? c) => c == null ? 0 : (c < cap ? c : cap);
    final high = threshold(t, 'conf_high');
    final low = threshold(t, 'conf_low');

    // Intent: the model's reading, scored by the classifier.
    if (answer.intent case final a?) {
      final p = conf(_probability(a, intent.wire));
      confidence['intent'] = p;
      if (p < threshold(t, 'conf_intent_min')) listedMissing.add('intent');
    }

    String? pick(ChoiceAnswer? a, String field, String confKey) {
      // `unspecified` is the catch-all "the message does not say"
      // (AI_PIPELINE 7): an answer about the message, not about the field.
      if (a == null || a.choice == null || a.choice == unspecifiedChoice) {
        return null;
      }
      final c = conf(a.confidence);
      confidence[confKey] = c;
      if (c < low) return null;
      if (c < high) guessed.add(field);
      return a.choice;
    }

    if (answer.account?.probabilities case final probs?) {
      accountRanking = [
        for (final e
            in probs.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
          e.key,
      ];
    }
    if (accountId == null) {
      accountScored = answer.account?.choice != null;
      final id = pick(answer.account, 'accountId', 'account');
      final account = snap.activeAccount(id);
      // An account holds only its own currency: a guessed currency follows
      // the account; a written one rules the account out.
      if (account != null &&
          (currency == null || _followAccountCurrency(account))) {
        accountId = account.id;
      } else {
        guessed.remove('accountId');
      }
    }
    if (_isTransfer && toAccountId == null) {
      toAccountScored = answer.toAccount?.choice != null;
      // Its own confidence key: `DraftConfidence.account` is the source's.
      final id = pick(answer.toAccount, 'toAccountId', 'toAccount');
      if (snap.activeAccount(id) != null && id != accountId) {
        toAccountId = id;
      } else {
        guessed.remove('toAccountId');
      }
    }
    if (_hasCategory && categoryId == null) {
      categoryScored = answer.category?.choice != null;
      final c = snap.activeCategory(
        pick(answer.category, 'categoryId', 'category'),
      );
      if (c != null) {
        categoryId = c.id;
      } else {
        guessed.remove('categoryId');
      }
    }
    if (who == null) {
      final w = pick(answer.who, 'who', 'who');
      if (w != null && whoValues.contains(w)) {
        who = w;
      } else {
        guessed.remove('who');
      }
    }
    if (_hasPerson && personId == null) {
      final p = snap.person(pick(answer.person, 'personId', 'person'));
      if (p != null) {
        personId = p.id;
      } else {
        guessed.remove('personId');
      }
    }
    if (answer.isRecurring?.probability case final p?
        when p >= threshold(t, 'recurring_offer')) {
      recurring = RecurringHint(probability: p, unit: 'month', interval: 1);
    }
    // The hint names the entry the classifier judged (`duplicate_of`),
    // never a guess of ours.
    if (answer.duplicate?.probability case final p?
        when p >= threshold(t, 'dup_warn')) {
      if (answer.duplicateOf case final txnId? when txnId.isNotEmpty) {
        duplicate = DuplicateHint(txnId: txnId, probability: p);
      }
    }
  }

  static double? _probability(ChoiceAnswer a, String key) {
    final p = a.probabilities?[key];
    if (p != null) return p.toDouble();
    return a.choice == key ? a.confidence : 0;
  }

  Future<void> _convert(XpenseContext context, ToolDeps deps) async {
    final amount = amountMinor;
    final code = currency;
    final day = occurredOn;
    if (amount == null || code == null || day == null) return;
    if (code == snap.baseCurrency) return;
    final FxDay? rate;
    try {
      rate = await deps.reader.fxRateOn(context.hid, day);
    } on HouseholdUnavailable {
      return;
    }
    if (rate == null) return; // the phone asks for the day's rate
    final from = Currency.tryParse(code);
    final base = Currency.tryParse(snap.baseCurrency);
    if (from == null || base == null) return;
    final parsed = FxRate.parse('USD/IQD', rate.usdIqd);
    if (parsed case Ok(value: final fxRate)) {
      if (toBaseAmount(Money(amount, from), base, rate: fxRate) case Ok(
        value: final converted,
      )) {
        fx = FxQuote(
          pair: 'USD/IQD',
          pairRate: fxRate.rateString,
          source: rate.kind,
          asOf: rate.date,
          baseAmountMinor: converted.minorUnits,
        );
      }
    }
  }

  EntryDraft build() {
    final base = EntryDraft(
      id: id,
      intent: intent.wire,
      amountMinor: amountMinor,
      currency: currency,
      accountId: accountId,
      toAccountId: toAccountId,
      categoryId: categoryId,
      who: who,
      occurredOn: occurredOn,
      title: _title(),
      personName: entry.person,
      personId: personId,
      fx: fx,
      confidence: confidence.isEmpty
          ? null
          : DraftConfidence(
              intent: confidence['intent'],
              category: confidence['category'],
              account: confidence['account'],
              who: confidence['who'],
            ),
      guessed: guessed.isEmpty ? null : (guessed.toList()..sort()),
      missing: listedMissing.isEmpty ? null : listedMissing.toList(),
      duplicate: duplicate,
      recurring: recurring,
      origin: 'agent',
    );
    final missing = missingFields(base)
      ..sort((a, b) => _order(a).compareTo(_order(b)));
    return EntryDraft.fromJson(
      {...base.toJson(), 'missing': missing.isEmpty ? null : missing}
        ..removeWhere((_, v) => v == null),
    );
  }

  String? _title() {
    final t = entry.title?.trim();
    if (t == null || t.isEmpty) return null;
    return t.length > 80 ? t.substring(0, 80) : t;
  }
}

int _order(String field) {
  final i = followUpOrder.indexOf(field);
  return i < 0 ? followUpOrder.length : i;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Iterable<String> _words(String s) => s.split(' ');

/// Words that carry no meaning in an account hint.
const _fillerWords = {'the', 'my', 'our', 'from', 'with', 'card', 'account'};

/// Words that say an entry is shared.
const _jointCues = {'we', 'our', 'us', 'joint', 'together', 'shared'};

/// Words that say an entry is the speaker's own.
const _meCues = {'i', 'my', 'me', 'mine', 'myself'};

/// Whether [text] contains [phrase] (a slug's underscores read as spaces).
bool _mentions(String text, String phrase) {
  final p = _norm(phrase.replaceAll('_', ' '));
  return p.isNotEmpty && ' ${_norm(text)} '.contains(' $p ');
}

/// Fields a follow-up question may ask. Amount, currency and date are
/// edited on the slip itself (A2UI_CATALOG 3.2).
const askableFields = {
  'intent',
  'accountId',
  'toAccountId',
  'categoryId',
  'personName',
};

/// The single follow-up of this turn: the first draft with a missing
/// askable field, its first such field in [followUpOrder], with up to
/// four options.
FollowUp? _firstFollowUp(
  List<EntryDraft> drafts,
  List<_DraftBuilder> builders,
) {
  for (final (i, d) in drafts.indexed) {
    final askable = [
      for (final f in d.missing ?? const <String>[])
        if (askableFields.contains(f)) f,
    ];
    if (askable.isEmpty) continue;
    final field = askable.first;
    final snap = builders[i].snap;
    // The classifier's likeliest accounts first, then list order.
    final rank = builders[i].accountRanking;
    int order(HouseholdAccount a) {
      final r = rank.indexOf(a.id);
      return r < 0 ? rank.length + snap.activeAccounts.indexOf(a) : r;
    }

    final ranked = [...snap.activeAccounts]
      ..sort((a, b) => order(a).compareTo(order(b)));
    final options = switch (field) {
      'accountId' => [
        for (final a in ranked)
          if (d.currency == null || a.currency == d.currency)
            FollowUpOption(label: a.name, value: a.id),
      ],
      // A transfer may arrive in another currency (`toAmountMinor`,
      // DATA_MODEL 2.5); never offer the source account.
      'toAccountId' => [
        for (final a in ranked)
          if (a.id != d.accountId) FollowUpOption(label: a.name, value: a.id),
      ],
      'categoryId' => const <FollowUpOption>[],
      _ => const <FollowUpOption>[],
    };
    return FollowUp(
      draftId: d.id,
      index: i,
      field: field,
      // Up to four: a ChoicePrompt takes 2 to 5 options.
      options: options.isEmpty ? null : options.take(4).toList(),
    );
  }
  return null;
}
