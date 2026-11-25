/// Builds the Decisions request for one message (AI_PIPELINE 7, WP-S4).
///
/// Option keys are ids or slugs only; names, groups and examples live in the
/// descriptions, because the model never sees the keys. Every choice has a
/// catch-all. Only `model`, `input` and `questions` are sent: the API
/// rejects any other field.
library;

import 'package:meta/meta.dart';
import 'package:xpense_agent/decide/category_examples.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_agent/decide/duplicates.dart';
import 'package:xpense_agent/decide/household_profile.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Keys the API accepts for questions and options (AI_PIPELINE 7).
final RegExp optionKeyPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// The API allows 2 to 255 options per choice question.
const int maxOptions = 255;

/// The fewest options a choice question may carry.
const int minOptions = 2;

/// Catch-all key for `account`, `to_account` and `who`.
const String unspecifiedKey = 'unspecified';

/// Catch-all keys for `person`.
const String noPersonKey = 'none';

/// A person who is not in the household's list.
const String otherPersonKey = 'other_person';

/// One-line descriptions of the 12 intents (AI_PIPELINE 4), as WP-S4
/// tested them. `other` is the catch-all.
const Map<String, String> intentCriteria = {
  'expense': 'Money spent on goods, services or bills.',
  'income':
      'Money received and kept: salary, freelance pay, a gift received, a '
      'refund, a sale.',
  'transfer':
      "Money moved between the household's own or joint accounts, including "
      'cash withdrawals and currency exchange.',
  'savings_move': 'Money put into or taken out of a savings goal.',
  'loan_given': 'Money lent to someone who is expected to pay it back.',
  'loan_taken': 'Money borrowed from someone or a bank, to be paid back.',
  'repayment_received': 'Someone paying back money they owed us.',
  'repayment_made':
      'Us paying back money we borrowed, or paying an instalment on a loan '
      'or debt.',
  'adjustment': 'Correcting an account balance or setting an opening balance.',
  'question':
      'A question about past spending, income, balances, budgets or entries.',
  'command':
      'A request to edit, delete or undo an entry, set a budget, create a '
      'goal or change a setting.',
  'other': 'Greeting, chit-chat, unclear, or not about household money.',
};

/// Question instructions. `intent` to `is_recurring` are AI_PIPELINE 7 word
/// for word (WP-S4 tested them); `duplicate` is WP-S4's v2 wording;
/// `to_account` and `person` are new and untested live before WP-33.
const Map<DecideQuestion, String> instructions = {
  .intent: 'What kind of money event does the message describe?',
  .category: 'Which category fits this spending or income best?',
  .account: 'Which account was the money paid from or received into?',
  .toAccount:
      'If money was moved between accounts or into a savings goal, which '
      'account did it go into?',
  .who: 'Whose spending or income is this?',
  .person:
      'Which person did the money go to or come from, as a loan, a '
      'repayment, a gift or support?',
  .multiEntry: 'Does the message describe more than one separate money event?',
  .repayable:
      'Money went to or came from a person. Is it expected to be paid back?',
  .needsFollowup:
      'Is information that is essential to record this event missing or '
      'ambiguous?',
  .isRecurring:
      'Is this a payment or income that normally repeats every month or week?',
  .duplicate:
      'Do the message and one of the recent entries describe the same '
      'real-world payment, so that saving the message would record it twice?',
};

/// The `account` wording when `to_account` is asked too: the source side
/// only (WP-S4 recommendation 3).
const String accountFromInstructions =
    'Which account did the money come from? For income, which account '
    'received it.';

/// Yes/no criteria (`true_description`, `false_description`), as WP-S4
/// tested them.
const Map<DecideQuestion, Map<String, String>> yesNoCriteria = {
  .multiEntry: {
    'true_description':
        'Two or more separate payments, incomes or transfers are described.',
    'false_description':
        'Exactly one money event, or none (a question or a command).',
  },
  .repayable: {
    'true_description': 'A loan: the money is expected to come back.',
    'false_description':
        'A gift, a payment for something, or a repayment of an earlier loan.',
  },
  .needsFollowup: {
    'true_description':
        'The amount is missing, or it is unclear whether money was spent, '
        'received, lent or borrowed, or what it was for.',
    'false_description':
        'The amount and the kind of event are clear; the account may be '
        'left to the default.',
  },
  .isRecurring: {
    'true_description':
        'A regular bill, subscription, rent, instalment or salary.',
    'false_description': 'A one-off or occasional purchase or event.',
  },
  .duplicate: {
    'true_description':
        'Same kind of payment, same amount and same purpose, person or '
        'merchant as a listed entry, even if that entry is dated a day '
        'earlier: it may have been saved already.',
    'false_description':
        'A separate event: a different purpose, person or merchant, or a '
        'routine purchase that is normally made again (bread, taxi rides).',
  },
};

/// The choice questions; every other key is yes/no.
const Set<DecideQuestion> choiceQuestions = {
  .intent,
  .category,
  .account,
  .toAccount,
  .who,
  .person,
};

/// One message ready to send: the shared input, the questions, and the
/// option keys offered per choice question (to check answers against).
@immutable
final class DecideRequestPlan {
  /// Creates a plan.
  const new({
    required this.input,
    required this.questions,
    required this.options,
  });

  /// The shared `input` text.
  final String input;

  /// The `questions` map, keyed by question key.
  final Map<String, Map<String, Object?>> questions;

  /// Option keys per choice question.
  final Map<DecideQuestion, Set<String>> options;

  /// The questions asked, in request order.
  Iterable<DecideQuestion> get asked =>
      questions.keys.map(DecideQuestion.byKey).nonNulls;

  /// The request body for [model]: exactly the three fields the API
  /// defines.
  Map<String, Object?> body(String model) => {
    'model': model,
    'input': input,
    'questions': questions,
  };
}

/// A household-local calendar day.
typedef LocalDay = ({int year, int month, int day});

/// Formats [d] as `YYYY-MM-DD`.
String isoDay(LocalDay d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// Parses `YYYY-MM-DD`, or null for anything else or a day that does not
/// exist.
LocalDay? parseDay(String? s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s ?? '');
  if (m == null) return null;
  final (y, mo, da) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  final d = DateTime.utc(y, mo, da);
  // Reject dates that do not exist, such as 2026-02-30.
  if (d.year != y || d.month != mo || d.day != da) return null;
  return (year: y, month: mo, day: da);
}

/// [d] moved by [days].
LocalDay addDays(LocalDay d, int days) {
  final t = DateTime.utc(d.year, d.month, d.day + days);
  return (year: t.year, month: t.month, day: t.day);
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _weekday(LocalDay d) =>
    _weekdays[DateTime.utc(d.year, d.month, d.day).weekday - 1];

String _two(int n) => n.toString().padLeft(2, '0');

/// Displays an amount in minor units, for example `IQD 10,000` or
/// `USD 42.80`. Unknown codes show the raw minor units.
String displayAmount(int amountMinor, String currencyCode) {
  final currency = Currency.tryParse(currencyCode);
  if (currency == null) return '$currencyCode $amountMinor (minor units)';
  final major = Money(amountMinor, currency).toMajorString();
  final dot = major.indexOf('.');
  final whole = dot < 0 ? major : major.substring(0, dot);
  final frac = dot < 0 ? '' : major.substring(dot);
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${currency.code} $grouped$frac';
}

/// Builds the request plan for one message.
///
/// [speakerUid] is the caller; [today] is the household-local date.
/// `duplicate` is dropped when [candidates] is empty. A choice question
/// left with fewer than two options (`account` or `to_account` in a
/// household with no account whose id the API accepts) is dropped too: the
/// API takes 2 to 255 options per choice and has no free-text question, so
/// the field is left to the parser and the phone's pickers.
DecideRequestPlan buildPlan({
  required HouseholdProfile profile,
  required String speakerUid,
  required LocalDay today,
  required String text,
  required Set<DecideQuestion> ask,
  DecideParsed? parsed,
  List<DuplicateCandidate> candidates = const [],
  SameAmount? alsoAs,
}) {
  final speaker = profile.member(speakerUid);
  final partner = [
    for (final m in profile.members)
      if (m.uid != speakerUid) m,
  ].firstOrNull;
  final options = <DecideQuestion, Map<String, String>>{
    for (final q in DecideQuestion.values)
      if (ask.contains(q) && choiceQuestions.contains(q))
        if (_criteria(q, profile, speaker: speaker, partner: partner)
            case final criteria when criteria.length >= minOptions)
          q: criteria,
  };
  final asked = [
    for (final q in DecideQuestion.values)
      if (ask.contains(q))
        if (q != .duplicate || candidates.isNotEmpty)
          if (!choiceQuestions.contains(q) || options.containsKey(q)) q,
  ];
  return DecideRequestPlan(
    input: sharedInput(
      profile: profile,
      speaker: speaker,
      partner: partner,
      today: today,
      text: text,
      parsed: parsed,
      candidates: asked.contains(DecideQuestion.duplicate)
          ? candidates
          : const [],
      alsoAs: asked.contains(DecideQuestion.duplicate) ? alsoAs : null,
    ),
    questions: {
      for (final q in asked)
        q.key: {
          'type': choiceQuestions.contains(q) ? 'choice' : 'noul',
          'instructions':
              q == .account && asked.contains(DecideQuestion.toAccount)
              ? accountFromInstructions
              : instructions[q]!,
          'criteria': ?(options[q] ?? yesNoCriteria[q]),
        },
    },
    options: {
      for (final MapEntry(:key, :value) in options.entries)
        key: value.keys.toSet(),
    },
  );
}

/// The shared `input` text (AI_PIPELINE 7 format plus the people line).
String sharedInput({
  required HouseholdProfile profile,
  required ProfileMember? speaker,
  required ProfileMember? partner,
  required LocalDay today,
  required String text,
  DecideParsed? parsed,
  List<DuplicateCandidate> candidates = const [],
  SameAmount? alsoAs,
}) {
  // A recent entry saved in the other currency is compared with the amount
  // at the day's rate, so the model is told that figure too.
  final converted = alsoAs == null
      ? ''
      : ' (${displayAmount(alsoAs.amountMinor, alsoAs.currency)} at that '
            "day's rate)";
  final amount = switch (parsed) {
    DecideParsed(amountMinor: final int minor, currency: final String code) =>
      'amount ${displayAmount(minor, code)}$converted',
    _ => 'no amount',
  };
  final date = switch (parseDay(parsed?.date)) {
    final d? when d == today => 'today',
    final d? => isoDay(d),
    null => 'today',
  };
  final people = [
    for (final p in profile.people)
      if (p.memberUid == null) _personLabel(p),
  ];
  final b = StringBuffer()
    ..write(
      'Today: ${isoDay(today)} (${_weekday(today)}). '
      'Household currency: ${profile.baseCurrency}. '
      'Speaker: ${speaker?.name ?? 'the speaker'} (me).',
    )
    ..writeln(partner == null ? '' : ' Partner: ${partner.name}.');
  if (people.isNotEmpty) b.writeln('People: ${people.join(', ')}.');
  b
    ..writeln('Already parsed: $amount, date $date.')
    // Triple quotes cannot be closed from inside the message.
    ..writeln('Message: """${text.replaceAll('"""', '"')}"""');
  if (candidates.isNotEmpty) {
    b.writeln('Recent entries:');
    for (final c in candidates) {
      final parts = [
        if (c.amountMinor != null && c.currency != null)
          displayAmount(c.amountMinor!, c.currency!),
        ?c.occurredOn,
        if (c.title case final t? when t.isNotEmpty) t,
      ];
      b.writeln('- ${parts.join(', ')}');
    }
  }
  return b.toString().trimRight();
}

String _personLabel(ProfilePerson p) =>
    p.aliases.isEmpty ? p.name : '${p.name} (also ${p.aliases.join(', ')})';

Map<String, String> _criteria(
  DecideQuestion q,
  HouseholdProfile profile, {
  required ProfileMember? speaker,
  required ProfileMember? partner,
}) => switch (q) {
  .intent => intentCriteria,
  .category => _categoryCriteria(profile),
  .account || .toAccount => _accountCriteria(
    profile,
    speaker: speaker,
    partner: partner,
    catchAll: q == .account
        ? 'The message does not say which account.'
        : 'The message does not say, or no money moved between accounts.',
  ),
  .who => {
    'me': '${speaker?.name ?? 'The speaker'}, the speaker, for themselves.',
    if (partner != null) 'partner': '${partner.name}, the partner.',
    'joint': 'Both of them, for the shared household.',
    unspecifiedKey: 'The message does not say.',
  },
  .person => _personCriteria(profile),
  _ => throw ArgumentError.value(q, 'q', 'not a choice question'),
};

Map<String, String> _categoryCriteria(HouseholdProfile profile) {
  final byId = {for (final c in profile.categories) c.id: c};
  final catchAll = {
    for (final c in profile.categories)
      if (c.slug == otherExpenseSlug || c.slug == otherIncomeSlug) c.slug: c,
  };
  final hasChildren = {for (final c in profile.categories) ?c.parentId};
  final out = <String, String>{};
  void add(String key, String description) {
    if (optionKeyPattern.hasMatch(key) && out.length < maxOptions - 2) {
      out[key] = description;
    }
  }

  for (final c in profile.categories) {
    if (catchAll.containsValue(c)) continue;
    // Groups with sub-categories are left out: WP-S4 found the 36 leaves
    // as accurate as all 45 slugs, with higher confidence and fewer tokens.
    if (c.isGroup && hasChildren.contains(c.id)) continue;
    final kind = c.kind == .expense ? 'Spending' : 'Income';
    final group = switch (byId[c.parentId]) {
      final g? => ' (${g.name})',
      null => '',
    };
    final examples = categoryExamples[c.slug];
    add(
      c.id,
      '$kind: ${c.name}$group.${examples == null ? '' : ' Examples: '
                '$examples.'}',
    );
  }
  // The two catch-alls always exist, under the household's ids when it has
  // them and under the slug otherwise.
  out[catchAll[otherExpenseSlug]?.id ?? otherExpenseSlug] =
      'Spending: Other. Examples: ${categoryExamples[otherExpenseSlug]}.';
  out[catchAll[otherIncomeSlug]?.id ?? otherIncomeSlug] =
      'Income: Other. Examples: ${categoryExamples[otherIncomeSlug]}.';
  return out;
}

Map<String, String> _accountCriteria(
  HouseholdProfile profile, {
  required ProfileMember? speaker,
  required ProfileMember? partner,
  required String catchAll,
}) {
  final out = <String, String>{};
  for (final a in profile.accounts) {
    if (!optionKeyPattern.hasMatch(a.id) || a.id == unspecifiedKey) continue;
    if (out.length >= maxOptions - 1) break;
    final whose = a.joint
        ? 'joint (shared by ${_names(speaker, partner)})'
        : a.ownerUid == speaker?.uid
        ? "mine (${speaker?.name ?? 'the speaker'}'s)"
        : "partner's (${partner?.name ?? 'the partner'}'s)";
    out[a.id] = '${a.name}, ${a.currency}, ${a.kind}, $whose';
  }
  out[unspecifiedKey] = catchAll;
  return out;
}

String _names(ProfileMember? a, ProfileMember? b) =>
    [?a?.name, ?b?.name].join(' and ');

Map<String, String> _personCriteria(HouseholdProfile profile) {
  final out = <String, String>{};
  for (final p in profile.people) {
    if (!optionKeyPattern.hasMatch(p.id) ||
        p.id == noPersonKey ||
        p.id == otherPersonKey) {
      continue;
    }
    if (out.length >= maxOptions - 2) break;
    out[p.id] = p.memberUid == null
        ? _personLabel(p)
        : '${_personLabel(p)}, a household member';
  }
  out[otherPersonKey] = 'Someone named in the message who is not listed.';
  out[noPersonKey] = 'No person is involved, or none is named.';
  return out;
}
