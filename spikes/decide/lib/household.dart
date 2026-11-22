/// The fixture household the spike classifies against: two members, seven
/// accounts, five people and the default category tree (AI_PIPELINE 4).
///
/// Names are fictional. Account ids are opaque, like Firestore ids, because
/// the Decisions API never shows option keys to the model: everything it
/// knows about an option is in the description.
library;

import 'package:clock/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// "Today" for every case: Sunday 22 November 2026, 18:00 household time.
final DateTime spikeNow = DateTime(2026, 11, 22, 18);

const String speakerName = 'Dara';
const String partnerName = 'Shilan';
const String householdCurrency = 'USD';

/// One account as the proxy would describe it.
final class FixtureAccount {
  const new({
    required this.id,
    required this.name,
    required this.currency,
    required this.owner,
    required this.kind,
    this.aliases = const [],
    this.note,
  });

  final String id;
  final String name;
  final Currency currency;

  /// `mine`, `partner` or `joint`.
  final String owner;

  /// `cash`, `bank`, `credit`, `savings` or `other`.
  final String kind;
  final List<String> aliases;
  final String? note;

  /// The option description, as AI_PIPELINE 7 suggests:
  /// "Cash wallet, IQD, mine".
  String get description {
    final whose = switch (owner) {
      'mine' => "mine ($speakerName's)",
      'partner' => "partner's ($partnerName's)",
      _ => 'joint (shared by $speakerName and $partnerName)',
    };
    final extra = note == null ? '' : '; $note';
    return '$name, ${currency.code}, $whose$extra';
  }
}

const List<FixtureAccount> accounts = [
  FixtureAccount(
    id: 'k3Qw8ZpL1rT6yVb2nM0a',
    name: 'Cash wallet',
    currency: Currency.iqd,
    owner: 'mine',
    kind: 'cash',
    aliases: ['wallet', 'cash'],
  ),
  FixtureAccount(
    id: 'p9Xe4HcJ7uS2fD5gK1oB',
    name: 'Cash dollars',
    currency: Currency.usd,
    owner: 'mine',
    kind: 'cash',
    aliases: ['dollar cash'],
  ),
  FixtureAccount(
    id: 'm2Rt6YwN8qZ3vB7xL4cC',
    name: 'Checking account',
    currency: Currency.usd,
    owner: 'mine',
    kind: 'bank',
    aliases: ['checking', 'bank account'],
    note: 'bank account where salary arrives',
  ),
  FixtureAccount(
    id: 'j5Fh1KsD9aG4wE6rT8dD',
    name: 'Joint Visa card',
    currency: Currency.usd,
    owner: 'joint',
    kind: 'credit',
    aliases: ['joint card', 'visa'],
  ),
  FixtureAccount(
    id: 'v7Lp3QzX5cM9bN2kJ6eE',
    name: "Shilan's cash wallet",
    currency: Currency.iqd,
    owner: 'partner',
    kind: 'cash',
    aliases: ['her wallet', 'her cash'],
  ),
  FixtureAccount(
    id: 's4Gt8WrE2yU6iO1pA3fF',
    name: 'Savings account',
    currency: Currency.usd,
    owner: 'joint',
    kind: 'savings',
    aliases: ['savings'],
    note: 'holds the savings goals (vacation, car)',
  ),
  FixtureAccount(
    id: 'f1Nb5VcX7zL3kJ9hG2gG',
    name: 'FIB mobile wallet',
    currency: Currency.iqd,
    owner: 'mine',
    kind: 'bank',
    aliases: ['fib', 'fib wallet'],
    note: 'First Iraqi Bank app',
  ),
];

/// Short labels used in the dataset so cases stay readable.
const Map<String, String> accountLabels = {
  'cash_iqd': 'k3Qw8ZpL1rT6yVb2nM0a',
  'cash_usd': 'p9Xe4HcJ7uS2fD5gK1oB',
  'checking': 'm2Rt6YwN8qZ3vB7xL4cC',
  'joint_visa': 'j5Fh1KsD9aG4wE6rT8dD',
  'partner_cash': 'v7Lp3QzX5cM9bN2kJ6eE',
  'savings': 's4Gt8WrE2yU6iO1pA3fF',
  'fib': 'f1Nb5VcX7zL3kJ9hG2gG',
  'unspecified': 'unspecified',
};

/// A person the household deals with (not a member).
final class FixturePerson {
  const new(this.id, this.name, this.relation, [this.aliases = const []]);
  final String id;
  final String name;
  final String relation;
  final List<String> aliases;
}

const List<FixturePerson> people = [
  FixturePerson('pAlex', 'Alex', 'friend'),
  FixturePerson('pKarwan', 'Karwan', "Dara's brother", ['my brother']),
  FixturePerson('pRebin', 'Rebin', 'colleague'),
  FixturePerson('pAram', 'Aram', "Dara's uncle", ['uncle aram', 'my uncle']),
  FixturePerson('pMom', 'Mom', "Dara's mother", ['mum', 'my mom']),
];

/// The parser context for this household, as the phone would build it.
ParseContext parseContext() => ParseContext(
  clock: Clock.fixed(spikeNow),
  accounts: [
    for (final a in accounts)
      ParserAccount(
        id: a.id,
        name: a.name,
        currency: a.currency,
        kind: a.kind,
        aliases: a.aliases,
      ),
  ],
  people: [
    for (final p in people)
      ParserPerson(id: p.id, name: p.name, aliases: p.aliases),
  ],
  categories: [
    for (final c in defaultCategories)
      ParserCategory(id: c.slug, names: c.names, kind: c.kind.wire),
  ],
  defaultAccountId: accounts.first.id,
);
