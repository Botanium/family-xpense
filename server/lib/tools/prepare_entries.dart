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
        text: e.text ?? (texts.isEmpty ? '' : texts.last),
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
    // Currency, most reliable first: a currency word next to or about the
    // amount; the account the entry names; the model's reading; the
    // household base currency. Only the first two are not guesses.
    final hinted = _matchAccounts(entry.accountHint, null);
    final String code;
    if (found.source == CurrencySource.word && found.currency != null) {
      code = found.currency!.code;
    } else if (hinted.length == 1) {
      code = hinted.single.currency;
    } else {
      code = entry.currency ?? snap.baseCurrency;
      guessed.add('currency');
    }
    currency = code;
    final money = Money.parseMajor(
      found.value.toString(),
      Currency.tryParse(code)!,
    );
    if (money case Ok(:final value)) {
      amountMinor = value.minorUnits;
    } else {
      notes.add('$id: $code cannot hold the amount ${entry.amount}');
    }
  }

  void resolveWords() {
    // Account words.
    final accounts = _matchAccounts(entry.accountHint, currency);
    if (accounts.length == 1) {
      accountId = accounts.single.id;
      confidence['account'] = 1;
    }
    if (_isTransfer) {
      final to = _matchAccounts(entry.toAccountHint, null);
      if (to.length == 1 && to.single.id != accountId) {
        toAccountId = to.single.id;
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
    // Who.
    if (entry.who case final w?) {
      who = w;
      confidence['who'] = 1;
    }
    // Person.
    if (entry.person case final name?) {
      final p = _matchPerson(name);
      if (p != null) personId = p.id;
    }
    // Date.
    occurredOn = _resolveDate();
  }

  String _resolveDate() {
    for (final words in [entry.dateWords, text]) {
      if (words == null) continue;
      final mention = parseText(words, parseContext).dateMention;
      if (mention != null) return mention.date.iso;
    }
    return today;
  }

  List<HouseholdAccount> _matchAccounts(String? hint, String? currency) {
    if (hint == null || hint.trim().isEmpty) return const [];
    final h = _norm(hint);
    final byCurrency = [
      for (final a in snap.accounts)
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
      for (final c in snap.categories)
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
    final candidates = await _duplicateCandidates(context, deps);
    await _classify(context, deps, thresholds, candidates);
    // The model's category stands in, as a guess, when nothing better came.
    if (categoryId == null && modelCategory != null) {
      categoryId = modelCategory!.id;
      guessed.add('categoryId');
    }
    await _convert(context, deps);
  }

  Future<List<LedgerTxn>> _duplicateCandidates(
    XpenseContext context,
    ToolDeps deps,
  ) async {
    final amount = amountMinor;
    final day = occurredOn;
    if (amount == null || day == null) return const [];
    try {
      final txns = await deps.reader.transactions(
        context.hid,
        uid: context.uid,
        fromOn: addDays(day, -1),
        toOn: addDays(day, 1),
      );
      return [
        for (final t in txns.items)
          if (t.amountMinor == amount &&
              t.currency == currency &&
              (accountId == null || t.accountId == accountId))
            t,
      ].take(3).toList();
    } on HouseholdUnavailable catch (e) {
      _log.warning('duplicate search skipped: ${e.operation}');
      return const [];
    }
  }

  Future<void> _classify(
    XpenseContext context,
    ToolDeps deps,
    Thresholds t,
    List<LedgerTxn> candidates,
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
      if (candidates.isNotEmpty) DecideQuestion.duplicate,
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
        candidates: [
          for (final c in candidates)
            DuplicateCandidate(
              txnId: c.id,
              amountMinor: c.amountMinor,
              currency: c.currency,
              occurredOn: c.occurredOn,
              title: c.title,
            ),
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

    if (accountId == null) {
      final id = pick(answer.account, 'accountId', 'account');
      final account = snap.account(id);
      // Only an account in the entry's currency can hold it.
      if (account != null &&
          (currency == null || account.currency == currency)) {
        accountId = account.id;
      } else {
        guessed.remove('accountId');
      }
    }
    if (_isTransfer && toAccountId == null) {
      final id = pick(answer.toAccount, 'toAccountId', 'account');
      if (snap.account(id) != null && id != accountId) {
        toAccountId = id;
      } else {
        guessed.remove('toAccountId');
      }
    }
    if (_hasCategory && categoryId == null) {
      final c = snap.category(pick(answer.category, 'categoryId', 'category'));
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
    if (answer.duplicate?.probability case final p?
        when p >= threshold(t, 'dup_warn') && candidates.isNotEmpty) {
      duplicate = DuplicateHint(txnId: candidates.first.id, probability: p);
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
/// three options.
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
    final options = switch (field) {
      'accountId' || 'toAccountId' => [
        for (final a in snap.accounts)
          if (d.currency == null || a.currency == d.currency)
            FollowUpOption(label: a.name, value: a.id),
      ],
      'categoryId' => const <FollowUpOption>[],
      _ => const <FollowUpOption>[],
    };
    return FollowUp(
      draftId: d.id,
      index: i,
      field: field,
      options: options.isEmpty ? null : options.take(3).toList(),
    );
  }
  return null;
}
