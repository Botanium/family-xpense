/// The question set of AI_PIPELINE 7, built the way the `/decide` proxy
/// will build it: option keys are slugs or ids only, names and examples
/// live in the descriptions, and every choice has a catch-all.
library;

import 'package:wp_s4_decide/household.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// One-line descriptions of the 12 intents (AI_PIPELINE 4).
const Map<String, String> intentDescriptions = {
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

/// Typical examples per category slug; the proxy will hold these per
/// household (seeded with the tree, editable later).
const Map<String, String> categoryExamples = {
  'food': 'food in general',
  'groceries': 'supermarket, market, fruit, vegetables, meat, food shopping',
  'dining': 'restaurants, lunch or dinner out, takeaway, delivery, cafes',
  'bakery_tea': 'bread, samoon, bakery, tea, coffee, sweets',
  'home': 'home costs in general',
  'rent': 'house or flat rent',
  'electricity_generator':
      'electricity bill, neighbourhood generator fee (ampere), fuel for a '
      'home generator',
  'water': 'water bill, drinking water delivery',
  'internet_phone': 'internet, mobile credit, phone bill',
  'household_goods': 'furniture, appliances, kitchen items, cleaning supplies',
  'repairs': 'plumber, electrician, home repairs',
  'transport': 'transport in general',
  'fuel': 'petrol, benzine, diesel for the car',
  'taxi': 'taxi, ride hailing (Careem, Uber)',
  'car_maintenance': 'mechanic, car repair, tyres, oil change, car wash',
  'public_transport': 'bus, minibus, train',
  'family': 'family costs in general',
  'kids_school': 'school fees, books, school supplies, kindergarten, toys',
  'clothing': 'clothes, shoes',
  'health': 'doctor, pharmacy, medicine, hospital, dentist',
  'personal_care': 'barber, salon, cosmetics, toiletries',
  'social': 'social costs in general',
  'gifts': 'presents bought for others',
  'family_support': 'money given to support parents or relatives',
  'charity': 'donations, zakat, mosque, charity',
  'occasions': 'weddings, funerals, Eid, parties, celebrations',
  'leisure': 'leisure in general',
  'entertainment': 'cinema, games, outings, hobbies',
  'travel': 'flights, hotels, trips',
  'subscriptions': 'streaming, apps, memberships (Netflix, Spotify, gym)',
  'finance': 'financial costs in general',
  'fees': 'bank fees, transfer fees, card fees',
  'interest': 'interest paid',
  'taxes': 'taxes, government fees',
  'other_expense': 'spending that fits no other category',
  'earned': 'earned income in general',
  'salary': 'monthly salary, wages, bonus',
  'freelance': 'freelance or side work paid per job',
  'business': 'business or shop income',
  'received': 'money received in general',
  'gift_received': 'money given to us as a gift, Eid money',
  'refund': 'refunds, returned purchases, cashback',
  'sale': 'selling our own things',
  'rental_income': 'rent received from a tenant',
  'other_income': 'income that fits no other category',
};

/// Which category options the `category` question offers.
enum CategoryOptions {
  /// Sub-categories plus the two catch-alls (36 options): the primary run.
  leaves,

  /// Every slug including the groups (45 options): AI_PIPELINE 7 as written.
  all,
}

Map<String, String> categoryCriteria(CategoryOptions options) {
  final out = <String, String>{};
  for (final c in defaultCategories) {
    final isCatchAll = c.slug == otherExpenseSlug || c.slug == otherIncomeSlug;
    if (options == .leaves && c.isGroup && !isCatchAll) continue;
    final kind = c.kind == .expense ? 'Spending' : 'Income';
    final group = c.parentSlug == null
        ? ''
        : ' (${defaultCategory(c.parentSlug!)!.nameIn('en')})';
    out[c.slug] =
        '$kind: ${c.nameIn('en')}$group. Examples: ${categoryExamples[c.slug]}.';
  }
  return out;
}

Map<String, String> accountCriteria() => {
  for (final a in accounts) a.id: a.description,
  'unspecified': 'The message does not say which account.',
};

const Map<String, String> whoCriteria = {
  'me': '$speakerName, the speaker, for themselves.',
  'partner': '$partnerName, the partner.',
  'joint': 'Both of them, for the shared household.',
  'unspecified': 'The message does not say.',
};

/// Question instructions, exactly as in AI_PIPELINE 7.
const Map<String, String> instructions = {
  'intent': 'What kind of money event does the message describe?',
  'category': 'Which category fits this spending or income best?',
  'account': 'Which account was the money paid from or received into?',
  'who': 'Whose spending or income is this?',
  'multi_entry':
      'Does the message describe more than one separate money event?',
  'repayable':
      'Money went to or came from a person. Is it expected to be paid back?',
  'needs_followup':
      'Is information that is essential to record this event missing or '
      'ambiguous?',
  'is_recurring':
      'Is this a payment or income that normally repeats every month or week?',
  'duplicate':
      'Is the message the same event as one of the listed recent entries?',
};

/// Yes/no criteria. The guide recommends describing both outcomes.
const Map<String, Map<String, String>> noulCriteria = {
  'multi_entry': {
    'true_description':
        'Two or more separate payments, incomes or transfers are described.',
    'false_description':
        'Exactly one money event, or none (a question or a command).',
  },
  'repayable': {
    'true_description': 'A loan: the money is expected to come back.',
    'false_description':
        'A gift, a payment for something, or a repayment of an earlier loan.',
  },
  'needs_followup': {
    'true_description':
        'The amount is missing, or it is unclear whether money was spent, '
        'received, lent or borrowed, or what it was for.',
    'false_description':
        'The amount and the kind of event are clear; the account may be '
        'left to the default.',
  },
  'is_recurring': {
    'true_description':
        'A regular bill, subscription, rent, instalment or salary.',
    'false_description': 'A one-off or occasional purchase or event.',
  },
  'duplicate': {
    'true_description':
        'The message records the same payment as a listed entry.',
    'false_description': 'The message is a new, separate event.',
  },
};

/// A recent saved entry offered as a duplicate candidate.
final class Candidate {
  const new({
    required this.id,
    required this.amount,
    required this.date,
    required this.title,
  });

  factory fromJson(Map<String, Object?> j) => Candidate(
    id: j['id']! as String,
    amount: j['amount']! as String,
    date: j['date']! as String,
    title: j['title']! as String,
  );

  final String id;

  /// Display form, for example `USD 42.80`.
  final String amount;
  final String date;
  final String title;
}

const List<String> _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The shared `input` text (AI_PIPELINE 7), from the fast parse.
String sharedInput(
  String message,
  FastParse parse, {
  List<Candidate> candidates = const [],
}) {
  final today = spikeNow;
  final iso =
      '${today.year}-${_two(today.month)}-${_two(today.day)} '
      '(${_weekdays[today.weekday - 1]})';
  final amounts = [
    for (final a in parse.amounts)
      '${a.currency?.code ?? 'unknown currency'} ${a.value}'
          '${a.droppedThousands ? ' (read as thousands)' : ''}',
  ];
  final parsedAmount = switch (amounts.length) {
    0 => 'no amount',
    1 => 'amount ${amounts.single}',
    _ => 'amounts ${amounts.join(', ')}',
  };
  final date = parse.dateMention == null ? 'today' : parse.date.iso;
  final b = StringBuffer()
    ..writeln(
      'Today: $iso. Household currency: $householdCurrency. '
      'Speaker: $speakerName (me). Partner: $partnerName.',
    )
    ..writeln(
      'People: ${[for (final p in people) '${p.name} (${p.relation})'].join(', ')}.',
    )
    ..writeln('Already parsed: $parsedAmount, date $date.')
    ..writeln('Message: """$message"""');
  if (candidates.isNotEmpty) {
    b.writeln('Recent entries:');
    for (final c in candidates) {
      b.writeln('- ${c.amount}, ${c.date}, ${c.title}');
    }
  }
  return b.toString().trimRight();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Builds the `questions` map for [keys].
Map<String, Object?> buildQuestions(
  Iterable<String> keys, {
  CategoryOptions categoryOptions = .leaves,
}) => {for (final key in keys) key: _question(key, categoryOptions)};

Map<String, Object?> _question(String key, CategoryOptions categoryOptions) {
  final criteria = switch (key) {
    'intent' => intentDescriptions,
    'category' => categoryCriteria(categoryOptions),
    'account' => accountCriteria(),
    'who' => whoCriteria,
    _ => null,
  };
  if (criteria != null) {
    return {
      'type': 'choice',
      'instructions': instructions[key],
      'criteria': criteria,
    };
  }
  return {
    'type': 'noul',
    'instructions': instructions[key],
    'criteria': ?noulCriteria[key],
  };
}

/// The keys asked for one message, per the rules of AI_PIPELINE 7:
/// `repayable` only when a person is detected, `duplicate` only with
/// candidates. The spike asks every other key on every message so each
/// question can be scored; the proxy will skip settled fields.
List<String> questionKeysFor(FastParse parse, {required bool hasCandidates}) {
  final personDetected =
      parse.signals.hasPersonTransfer ||
      parse.hints.any((h) => h.kind == HintKind.person);
  return [
    'intent',
    'category',
    'account',
    'who',
    'multi_entry',
    if (personDetected) 'repayable',
    'needs_followup',
    'is_recurring',
    if (hasCandidates) 'duplicate',
  ];
}
