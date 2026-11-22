/// Word tables for the fast parser, keyed by language code (AI_PIPELINE 5).
///
/// Only English is filled for now (D-36). A new language adds one
/// [ParserLexicon] to [parserLexicons]; the parser code does not change.
/// Every entry is already normalised (lower case, single spaces), because
/// the parser matches against normalised text.
library;

import 'package:meta/meta.dart';
import 'package:xpense_shared/money/currency.dart';

/// One language's word tables for the fast parser.
@immutable
final class ParserLexicon {
  /// Creates a lexicon. Every phrase must be normalised.
  const new({
    required this.languageCode,
    required this.units,
    required this.tens,
    required this.hundredWords,
    required this.scaleWords,
    required this.gluedSuffixes,
    required this.standaloneSuffixes,
    required this.halfWords,
    required this.quarterWords,
    required this.indefiniteArticles,
    required this.numberConnectives,
    required this.currencyWords,
    required this.prefixCurrencyWords,
    required this.gluedOnlyCurrencyWords,
    required this.currencyQualifiers,
    required this.minorUnitWords,
    required this.quantityUnits,
    required this.timeSuffixes,
    required this.ordinalSuffixes,
    required this.conjunctions,
    required this.activityVerbs,
    required this.questionPhrases,
    required this.questionLeads,
    required this.politePrefixes,
    required this.commandLeads,
    required this.commandPhrases,
    required this.transferVerbs,
    required this.relationWords,
    required this.stopWords,
    required this.accountWords,
    required this.whoWords,
    required this.intentCues,
    required this.payWords,
    required this.todayWords,
    required this.yesterdayWords,
    required this.dayBeforeYesterdayWords,
    required this.lastWords,
    required this.agoWords,
    required this.dayUnitWords,
    required this.weekUnitWords,
    required this.weekdays,
    required this.months,
    required this.receiptTotalWords,
    required this.receiptTotalExclusions,
    required this.receiptNonItemWords,
    required this.receiptMerchantSkipWords,
  });

  /// The language code this lexicon serves, for example `en`.
  final String languageCode;

  /// Number words from zero to nineteen.
  final Map<String, int> units;

  /// Multiples of ten from twenty to ninety.
  final Map<String, int> tens;

  /// Words for one hundred.
  final Set<String> hundredWords;

  /// Scale words and their factor (`thousand` 1,000, `million` 1,000,000).
  final Map<String, int> scaleWords;

  /// Suffixes written directly after digits (`5k`, `1.5m`) and their factor.
  final Map<String, int> gluedSuffixes;

  /// Suffix words allowed as a separate token after a number (`5 k`).
  final Map<String, int> standaloneSuffixes;

  /// Words for one half.
  final Set<String> halfWords;

  /// Words for one quarter.
  final Set<String> quarterWords;

  /// Articles that stand for "one" before a scale (`a thousand`).
  final Set<String> indefiniteArticles;

  /// Words that join number words (`three hundred and fifty`).
  final Set<String> numberConnectives;

  /// Currency words and the currency they name.
  final Map<String, Currency> currencyWords;

  /// Currency words that may precede the number (`$5`, `usd 50`).
  final Set<String> prefixCurrencyWords;

  /// Currency words accepted only when written right after the digits or
  /// as the next token (`25000 id`), because they are common words too.
  final Set<String> gluedOnlyCurrencyWords;

  /// Words that may sit before a currency word (`us dollars`).
  final Set<String> currencyQualifiers;

  /// Minor-unit words (`cents`): the currency and its scale divisor.
  final Map<String, Currency> minorUnitWords;

  /// Units that make a number a quantity, not money (`2 kg`).
  final Set<String> quantityUnits;

  /// Suffixes that make a number a time of day (`5pm`).
  final Set<String> timeSuffixes;

  /// Suffixes that make a number an ordinal (`5th`).
  final Set<String> ordinalSuffixes;

  /// Words that can join two clauses (`and`, `also`, `plus`).
  final Set<String> conjunctions;

  /// Verbs that make a clause an entry on their own (`spent`, `paid`).
  final Set<String> activityVerbs;

  /// Phrases anywhere in the text that mark a question.
  final List<String> questionPhrases;

  /// Words that mark a question when they open the message.
  final Set<String> questionLeads;

  /// Politeness openers removed before the command check (`please`).
  final List<String> politePrefixes;

  /// Imperative verbs that mark a command when they open the message.
  final Set<String> commandLeads;

  /// Phrases anywhere in the text that mark a command (`set budget`).
  final List<String> commandPhrases;

  /// Phrases for money moving to or from a person (`gave`, `paid back`).
  final List<String> transferVerbs;

  /// Words for relatives and friends that count as a person (`dad`).
  final Set<String> relationWords;

  /// Function words never taken as a name or a quantity noun.
  final Set<String> stopWords;

  /// Generic account words and the account kinds they point at
  /// (DATA_MODEL 2.4 kinds: cash, bank, credit, savings, other).
  final Map<String, List<String>> accountWords;

  /// Phrases that say whose money it is, and the `who` value.
  final Map<String, String> whoWords;

  /// Phrases that settle the intent on their own, and the intent wire value.
  final Map<String, String> intentCues;

  /// Bare "paid" verbs: an expense cue only when no person is named.
  final Set<String> payWords;

  /// Phrases for today.
  final List<String> todayWords;

  /// Phrases for yesterday.
  final List<String> yesterdayWords;

  /// Phrases for the day before yesterday.
  final List<String> dayBeforeYesterdayWords;

  /// Words for "last" before a weekday (`last friday`).
  final Set<String> lastWords;

  /// Words for "ago" (`3 days ago`).
  final Set<String> agoWords;

  /// Words for a day as a unit (`days`).
  final Set<String> dayUnitWords;

  /// Words for a week as a unit (`weeks`).
  final Set<String> weekUnitWords;

  /// Weekday words and their ISO number (Monday 1 to Sunday 7).
  final Map<String, int> weekdays;

  /// Month words and their number (1 to 12).
  final Map<String, int> months;

  /// Receipt words near the total (`total`, `amount due`).
  final List<String> receiptTotalWords;

  /// Receipt words that disqualify a total line (`subtotal`, `change`).
  final List<String> receiptTotalExclusions;

  /// Receipt words that make a priced row something other than an item.
  final List<String> receiptNonItemWords;

  /// Receipt words that disqualify a merchant line (`invoice`, `tel`).
  final List<String> receiptMerchantSkipWords;
}

/// The lexicons by language code. English only for now (D-36).
const Map<String, ParserLexicon> parserLexicons = {'en': englishLexicon};

/// The lexicon for [languageCode] (`en`, `en-US`, `en_GB`), or English when
/// the language has no lexicon yet.
ParserLexicon lexiconFor(String languageCode) {
  final primary = languageCode.toLowerCase().split(RegExp('[-_]')).first;
  return parserLexicons[primary] ?? englishLexicon;
}

/// The English lexicon.
const ParserLexicon englishLexicon = ParserLexicon(
  languageCode: 'en',
  units: {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
  },
  tens: {
    'twenty': 20,
    'thirty': 30,
    'forty': 40,
    'fourty': 40,
    'fifty': 50,
    'sixty': 60,
    'seventy': 70,
    'eighty': 80,
    'ninety': 90,
  },
  hundredWords: {'hundred'},
  scaleWords: {
    'thousand': 1000,
    'grand': 1000,
    'million': 1000000,
    'millions': 1000000,
    'thousands': 1000,
  },
  gluedSuffixes: {'k': 1000, 'm': 1000000, 'mn': 1000000, 'mil': 1000000},
  standaloneSuffixes: {'k': 1000, 'mn': 1000000, 'mil': 1000000},
  halfWords: {'half'},
  quarterWords: {'quarter'},
  indefiniteArticles: {'a', 'an'},
  numberConnectives: {'and'},
  currencyWords: {
    r'$': Currency.usd,
    'usd': Currency.usd,
    'dollar': Currency.usd,
    'dollars': Currency.usd,
    'buck': Currency.usd,
    'bucks': Currency.usd,
    'iqd': Currency.iqd,
    'dinar': Currency.iqd,
    'dinars': Currency.iqd,
    'id': Currency.iqd,
  },
  prefixCurrencyWords: {r'$', 'usd', 'iqd'},
  gluedOnlyCurrencyWords: {'id'},
  currencyQualifiers: {'us', 'american', 'iraqi'},
  minorUnitWords: {'cent': Currency.usd, 'cents': Currency.usd},
  quantityUnits: {
    'kg',
    'kgs',
    'kilo',
    'kilos',
    'kilogram',
    'kilograms',
    'g',
    'gram',
    'grams',
    'l',
    'liter',
    'liters',
    'litre',
    'litres',
    'ml',
    'km',
    'pcs',
    'pc',
    'piece',
    'pieces',
    'x',
    'times',
    'people',
    'persons',
    'days',
    'hours',
    'hrs',
    'hour',
    'minutes',
    'mins',
    'weeks',
    'months',
    'years',
    'nights',
    'percent',
  },
  timeSuffixes: {'am', 'pm', "o'clock", 'oclock'},
  ordinalSuffixes: {'st', 'nd', 'rd', 'th'},
  conjunctions: {'and', 'also', 'plus', '&', 'then'},
  activityVerbs: {
    'spent',
    'spend',
    'paid',
    'pay',
    'bought',
    'buy',
    'got',
    'received',
    'earned',
    'gave',
    'lent',
    'borrowed',
    'sent',
    'moved',
    'transferred',
    'saved',
    'withdrew',
    'deposited',
    'owe',
    'owes',
    'cost',
    'costs',
  },
  questionPhrases: [
    'how much',
    'how many',
    'what',
    'which',
    'how far',
    'where did',
    'when did',
  ],
  questionLeads: {
    'how',
    'what',
    'which',
    'who',
    'when',
    'where',
    'why',
    'did',
    'do',
    'does',
    'is',
    'are',
    'show',
    'list',
  },
  politePrefixes: [
    'please',
    'pls',
    'can you',
    'could you',
    'would you',
    'will you',
  ],
  commandLeads: {
    'delete',
    'remove',
    'undo',
    'redo',
    'change',
    'edit',
    'update',
    'rename',
    'cancel',
    'correct',
    'fix',
    'archive',
  },
  commandPhrases: [
    'set budget',
    'set a budget',
    'set the budget',
    'set my budget',
    'new budget',
    'create budget',
    'create a budget',
    'new goal',
    'create goal',
    'create a goal',
    'make a goal',
    'set a goal',
    'set goal',
    'add a goal',
    'change setting',
    'change the setting',
    'undo that',
    'undo last',
  ],
  transferVerbs: [
    'gave',
    'give',
    'given',
    'lent',
    'lend',
    'loaned',
    'loan',
    'borrowed',
    'borrow',
    'paid back',
    'pay back',
    'paid me back',
    'repaid',
    'repay',
    'owes',
    'owe',
    'owed',
    'sent',
    'send',
    'got back',
    'returned',
  ],
  relationWords: {
    'mom',
    'mum',
    'mother',
    'dad',
    'father',
    'brother',
    'sister',
    'uncle',
    'aunt',
    'auntie',
    'cousin',
    'friend',
    'neighbor',
    'neighbour',
    'colleague',
    'boss',
    'son',
    'daughter',
    'grandma',
    'grandpa',
    'grandmother',
    'grandfather',
    'wife',
    'husband',
    'nephew',
    'niece',
  },
  stopWords: {
    'i',
    "i'm",
    "i've",
    'me',
    'my',
    'mine',
    'we',
    'us',
    'our',
    'you',
    'your',
    'he',
    'she',
    'him',
    'her',
    'they',
    'them',
    'it',
    'the',
    'a',
    'an',
    'to',
    'from',
    'for',
    'on',
    'at',
    'in',
    'with',
    'by',
    'of',
    'and',
    'or',
    'back',
    'some',
    'this',
    'that',
    'today',
    'yesterday',
    'last',
    'ok',
    'okay',
    'hi',
    'hello',
    'please',
    'thanks',
  },
  accountWords: {
    'cash': ['cash'],
    'wallet': ['cash'],
    'card': ['credit', 'bank'],
    'credit card': ['credit'],
    'debit card': ['bank'],
    'visa': ['credit'],
    'mastercard': ['credit'],
    'bank': ['bank'],
    'savings': ['savings'],
  },
  whoWords: {
    'joint': 'joint',
    'shared': 'joint',
    'together': 'joint',
    'for the house': 'joint',
    'household': 'joint',
    'my wife': 'partner',
    'my husband': 'partner',
    'my partner': 'partner',
  },
  intentCues: {
    'spent': 'expense',
    'spend': 'expense',
    'bought': 'expense',
    'buy': 'expense',
    'purchased': 'expense',
    'paid for': 'expense',
    'cost': 'expense',
    'costs': 'expense',
    'earned': 'income',
    'got paid': 'income',
    'was paid': 'income',
    'lent': 'loan_given',
    'loaned': 'loan_given',
    'borrowed': 'loan_taken',
    'paid me back': 'repayment_received',
    'gave me back': 'repayment_received',
    'repaid me': 'repayment_received',
    'got back': 'repayment_received',
    'paid back': 'repayment_made',
    'repaid': 'repayment_made',
    'paid off': 'repayment_made',
    'transferred': 'transfer',
    'withdrew': 'transfer',
    'deposited': 'transfer',
    'saved': 'savings_move',
    'opening balance': 'adjustment',
  },
  payWords: {'paid', 'pay'},
  todayWords: [
    'today',
    'this morning',
    'this afternoon',
    'this evening',
    'tonight',
    'earlier today',
  ],
  yesterdayWords: ['yesterday', 'last night'],
  dayBeforeYesterdayWords: ['day before yesterday', 'the day before yesterday'],
  lastWords: {'last', 'past'},
  agoWords: {'ago'},
  dayUnitWords: {'day', 'days'},
  weekUnitWords: {'week', 'weeks'},
  weekdays: {
    'monday': 1,
    'mon': 1,
    'tuesday': 2,
    'tue': 2,
    'tues': 2,
    'wednesday': 3,
    'wed': 3,
    'thursday': 4,
    'thu': 4,
    'thur': 4,
    'thurs': 4,
    'friday': 5,
    'fri': 5,
    'saturday': 6,
    'sat': 6,
    'sunday': 7,
    'sun': 7,
  },
  months: {
    'january': 1,
    'jan': 1,
    'february': 2,
    'feb': 2,
    'march': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'may': 5,
    'june': 6,
    'jun': 6,
    'july': 7,
    'jul': 7,
    'august': 8,
    'aug': 8,
    'september': 9,
    'sep': 9,
    'sept': 9,
    'october': 10,
    'oct': 10,
    'november': 11,
    'nov': 11,
    'december': 12,
    'dec': 12,
  },
  receiptTotalWords: [
    'grand total',
    'total due',
    'amount due',
    'balance due',
    'total amount',
    'net total',
    'total payable',
    'to pay',
    'net amount',
    'total',
    'balance',
    'amount',
  ],
  receiptTotalExclusions: [
    'subtotal',
    'sub total',
    'sub-total',
    'total items',
    'total item',
    'total qty',
    'total quantity',
    'items',
    'tax',
    'vat',
    'discount',
    'saving',
    'savings',
    'change',
    'cash',
    'tendered',
    'received',
    'points',
  ],
  receiptNonItemWords: [
    'total',
    'subtotal',
    'sub total',
    'tax',
    'vat',
    'service',
    'discount',
    'cash',
    'change',
    'card',
    'visa',
    'mastercard',
    'tip',
    'balance',
    'amount',
    'tendered',
    'tel',
    'phone',
    'invoice',
    'receipt',
    'table',
    'cashier',
    'qty',
    'date',
    'time',
    'paid',
    'due',
    'rounding',
  ],
  receiptMerchantSkipWords: [
    'receipt',
    'invoice',
    'tax invoice',
    'welcome',
    'tel',
    'phone',
    'www',
    'http',
    'street',
    'road',
    'thank',
    'date',
    'time',
    'cashier',
    'order',
    'table',
    'vat',
  ],
);
