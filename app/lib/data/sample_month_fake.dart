// Sample entries for the fakes build: a month of spending, two salaries,
// rent and a savings move over the artboards' accounts
// (`FakeAccountsRepository.sampleAccounts`), so Home and Activity have
// something to show without Firebase. Not used in dev or prod builds.
import 'package:xpense_app/data/accounts_repository_fake.dart';
import 'package:xpense_app/data/write/memory_ledger_store.dart';

/// Puts a month of sample entries, from the 1st to [today], in [store]: a
/// salary each, rent, a savings move and daily spending, so Home and
/// Activity have something to show in the fakes build. All in USD.
void seedSampleMonth(MemoryLedgerStore store, DateTime today) {
  const viewer = FakeAccountsRepository.sampleViewer;
  const partner = FakeAccountsRepository.samplePartner;
  const both = [viewer, partner];
  var n = 0;
  void put({
    required int day,
    required String type,
    required int cents,
    required String account,
    required List<String> visibleTo,
    String merchant = '',
    String? category,
    String? who,
    String? goalId,
    String? toAccount,
  }) {
    final at = DateTime(today.year, today.month, day, 9 + n % 10, n % 60);
    store.seedTransaction('sample-${n++}', {
      'type': type,
      'amountMinor': cents,
      'currency': 'USD',
      'accountId': account,
      'toAccountId': ?toAccount,
      'baseAmountMinor': cents,
      'categoryId': category,
      'whoScope': who == null ? 'joint' : 'member',
      'whoUid': who,
      'occurredAt': at.toUtc(),
      'occurredOn':
          '${at.year}-${'${at.month}'.padLeft(2, '0')}-'
          '${'${at.day}'.padLeft(2, '0')}',
      'title': merchant,
      'goalId': goalId,
      'visibleTo': visibleTo,
      'source': 'manual',
      'deletedAt': null,
      'rev': 0,
    });
  }

  const daily = [18, 30, 12, 44, 22, 8, 26, 38, 14, 20, 52, 16, 24, 10, 34];
  for (var day = 1; day <= today.day; day++) {
    put(
      day: day,
      type: 'expense',
      cents: daily[(day - 1) % daily.length] * 450 + 85,
      account: 'acc-visa',
      visibleTo: both,
      merchant: day.isEven ? 'Costco' : 'Lunch',
      category: day.isEven ? 'groceries' : 'dining',
      who: day % 3 == 0 ? partner : viewer,
    );
  }
  put(
    day: 1,
    type: 'expense',
    cents: 140000,
    account: 'acc-visa',
    visibleTo: both,
    merchant: 'Rent',
    category: 'rent',
  );
  put(
    day: 1,
    type: 'income',
    cents: 320000,
    account: 'acc-checking',
    visibleTo: const [viewer],
    merchant: 'Salary',
    category: 'salary',
    who: viewer,
  );
  put(
    day: 1,
    type: 'income',
    cents: 245000,
    account: 'acc-sam-checking',
    visibleTo: both,
    merchant: 'Salary',
    category: 'salary',
    who: partner,
  );
  put(
    day: 1,
    type: 'transfer',
    cents: 65000,
    account: 'acc-checking',
    toAccount: 'acc-trip',
    visibleTo: both,
    merchant: 'Summer trip',
    goalId: 'goal-trip',
    who: viewer,
  );
}
