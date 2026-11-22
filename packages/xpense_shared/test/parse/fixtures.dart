import 'package:clock/clock.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// "Today" for every parser test: Sunday 22 November 2026, 14:30 local.
final DateTime fixtureNow = DateTime(2026, 11, 22, 14, 30);

/// [LocalDate] of [fixtureNow].
final LocalDate fixtureToday = LocalDate.fromDateTime(fixtureNow);

/// The fixture household's accounts.
const List<ParserAccount> fixtureAccounts = [
  ParserAccount(
    id: 'acc_cash',
    name: 'Cash wallet',
    currency: Currency.iqd,
    kind: 'cash',
  ),
  ParserAccount(
    id: 'acc_visa',
    name: 'Joint Visa ••4021',
    currency: Currency.usd,
    kind: 'credit',
    aliases: ['visa', 'the card'],
  ),
  ParserAccount(
    id: 'acc_bank',
    name: 'Rafidain bank',
    currency: Currency.iqd,
    kind: 'bank',
  ),
  ParserAccount(
    id: 'acc_savings',
    name: 'Trip fund',
    currency: Currency.usd,
    kind: 'savings',
  ),
];

/// The fixture household's people.
const List<ParserPerson> fixturePeople = [
  ParserPerson(id: 'p_alex', name: 'Alex'),
  ParserPerson(id: 'p_sara', name: 'Sara', aliases: ['sarah']),
  ParserPerson(id: 'p_dad', name: 'Abu Ali', aliases: ['dad']),
];

/// The fixture household's categories.
const List<ParserCategory> fixtureCategories = [
  ParserCategory(id: 'c_groceries', names: {'en': 'Groceries'}),
  ParserCategory(id: 'c_dining', names: {'en': 'Dining'}, aliases: ['lunch']),
  ParserCategory(id: 'c_rent', names: {'en': 'Rent'}),
  ParserCategory(id: 'c_fuel', names: {'en': 'Fuel'}, aliases: ['petrol']),
  ParserCategory(id: 'c_salary', names: {'en': 'Salary'}, kind: 'income'),
];

/// The fixture household's learned rules.
const List<ParserRule> fixtureRules = [
  ParserRule(
    id: 'r_costco',
    kind: RuleKind.merchant,
    pattern: 'Costco',
    categoryId: 'c_groceries',
    accountId: 'acc_visa',
  ),
  ParserRule(
    id: 'r_generator',
    kind: RuleKind.keyword,
    pattern: 'generator',
    categoryId: 'c_generator',
  ),
  ParserRule(
    id: 'r_alex',
    kind: RuleKind.person,
    pattern: 'alex',
    accountId: 'acc_cash',
  ),
  ParserRule(
    id: 'r_shop',
    kind: RuleKind.keyword,
    pattern: 'shop',
    categoryId: 'c_dining',
  ),
  ParserRule(
    id: 'r_carrefour',
    kind: RuleKind.merchant,
    pattern: 'carrefour',
    categoryId: 'c_groceries',
    intent: 'expense',
  ),
  ParserRule(
    id: 'r_mall',
    kind: RuleKind.merchant,
    pattern: 'city mall',
    who: 'joint',
  ),
];

/// A household whose default account is the IQD cash wallet.
ParseContext iqdHome({
  Attachment attachment = Attachment.none,
  List<ParserRule> rules = fixtureRules,
}) => ParseContext(
  clock: Clock.fixed(fixtureNow),
  accounts: fixtureAccounts,
  people: fixturePeople,
  categories: fixtureCategories,
  rules: rules,
  defaultAccountId: 'acc_cash',
  attachment: attachment,
);

/// The same household with the USD Visa as default.
ParseContext usdHome() => ParseContext(
  clock: Clock.fixed(fixtureNow),
  accounts: fixtureAccounts,
  people: fixturePeople,
  categories: fixtureCategories,
  rules: fixtureRules,
  defaultAccountId: 'acc_visa',
);

/// A context with no accounts, people, categories or rules.
ParseContext bareContext() => ParseContext(clock: Clock.fixed(fixtureNow));
