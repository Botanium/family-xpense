/// Representative inputs of the local builder, one per fixture in
/// `test/fixtures/surfaces/local_*.json` (A2UI_CATALOG 8). The fixtures are
/// shared with the app's golden tests and the `surfaceValid` evaluator.
library;

import 'package:xpense_shared/xpense_shared.dart';

/// The day every fixture is set on.
const String fixtureDay = '2026-11-22';

final EntryDraft _lunch = EntryDraft(
  id: 'd1',
  intent: 'expense',
  amountMinor: 10000,
  currency: 'IQD',
  categoryId: 'dining',
  who: 'me',
  occurredOn: fixtureDay,
  occurredTime: '13:20',
  title: 'Lunch with the kids',
  fx: FxQuote(
    pair: 'USD/IQD',
    pairRate: '1705',
    source: 'market',
    asOf: fixtureDay,
    baseAmountMinor: 587,
  ),
  confidence: DraftConfidence(intent: 0.97, category: 0.94, account: 0.31),
  missing: ['accountId'],
  origin: 'decisions',
);

/// Builder output by fixture name (without `local_` and `.json`).
final Map<String, List<Map<String, Object?>> Function()> localFixtures = {
  // A2UI_CATALOG 8: one draft with a missing account, heard by voice.
  'capture_missing_account': () => captureSurface(
    surfaceId: 'loc_cap_k3m9',
    transcript: const TranscriptData(
      text: 'Spent ten thousand dinars on lunch with the kids',
      seconds: 6,
    ),
    drafts: [_lunch],
  ),
  // Two entries in one message, one field guessed.
  'capture_two_entries': () => captureSurface(
    surfaceId: 'loc_cap_two',
    title: 'I found two things in that:',
    transcript: const TranscriptData(
      text: 'Got my salary, 3,200, and paid the rent, 1,400',
    ),
    drafts: [
      EntryDraft(
        id: 'd1',
        intent: 'income',
        amountMinor: 320000,
        currency: 'USD',
        categoryId: 'salary',
        accountId: 'acc_chk',
        who: 'me',
        occurredOn: fixtureDay,
        title: 'Salary',
        confidence: DraftConfidence(
          intent: 0.99,
          category: 0.97,
          account: 0.96,
        ),
        origin: 'parser',
      ),
      EntryDraft(
        id: 'd2',
        intent: 'expense',
        amountMinor: 140000,
        currency: 'USD',
        categoryId: 'rent',
        accountId: 'acc_chk',
        who: 'joint',
        occurredOn: fixtureDay,
        title: 'Rent',
        confidence: DraftConfidence(
          intent: 0.98,
          category: 0.99,
          account: 0.97,
          who: 0.62,
        ),
        guessed: ['who'],
        origin: 'decisions',
      ),
    ],
  ),
  // An intent question: the options change what the entry means.
  'capture_intent_question': () => captureSurface(
    surfaceId: 'loc_cap_p7x2',
    ask: ChoicePromptData.intent(
      question: 'Quick check, so I file it right: will Alex pay this back?',
      options: const [
        ChoiceOptionData(
          label: "Yes, it's a loan",
          value: 'loan_given',
          hint: 'Alex owes us',
        ),
        ChoiceOptionData(
          label: 'No, gift or payment',
          value: 'expense',
          hint: 'Expense',
        ),
        ChoiceOptionData(
          label: 'I was paying Alex back',
          value: 'repayment_made',
          hint: 'Debt',
        ),
      ],
    ),
    drafts: [
      EntryDraft(
        id: 'd1',
        intent: 'loan_given',
        amountMinor: 30000,
        currency: 'USD',
        personName: 'Alex',
        accountId: 'acc_chk',
        occurredOn: fixtureDay,
        missing: ['intent'],
        origin: 'parser',
      ),
    ],
  ),
  // A possible duplicate and a recurring guess on one slip.
  'capture_hints': () => captureSurface(
    surfaceId: 'loc_cap_hints',
    drafts: [
      EntryDraft(
        id: 'd1',
        intent: 'expense',
        amountMinor: 4500,
        currency: 'USD',
        categoryId: 'utilities',
        accountId: 'acc_chk',
        who: 'joint',
        occurredOn: fixtureDay,
        title: 'Internet',
        duplicate: DuplicateHint(txnId: 't_88', probability: 0.81),
        recurring: RecurringHint(
          probability: 0.92,
          unit: 'month',
          interval: 1,
          dayOfMonth: 5,
        ),
        origin: 'rule',
      ),
    ],
  ),
  // A receipt split by category: lines add up to 55,500, the total is
  // 60,500 (service), so the groups share the difference by allocate().
  'receipt_split': () {
    const receipt = SurfaceReceipt(
      merchant: 'Family Mart',
      occurredOn: fixtureDay,
      occurredTime: '18:05',
      currency: 'IQD',
      totalMinor: 60500,
      lines: [
        SurfaceReceiptLine(
          text: 'Rice 5kg',
          amountMinor: 18000,
          categoryId: 'groceries',
        ),
        SurfaceReceiptLine(
          text: 'Chicken',
          amountMinor: 14500,
          categoryId: 'groceries',
        ),
        SurfaceReceiptLine(
          text: 'Dish soap',
          amountMinor: 4000,
          categoryId: 'household',
        ),
        SurfaceReceiptLine(
          text: 'Birthday card',
          amountMinor: 19000,
          categoryId: 'gifts',
        ),
      ],
    );
    final template = EntryDraft(
      id: 'r',
      intent: 'expense',
      amountMinor: 60500,
      currency: 'IQD',
      accountId: 'acc_cash',
      who: 'joint',
      occurredOn: fixtureDay,
      occurredTime: '18:05',
      title: 'Family Mart',
      origin: 'parser',
    );
    final drafts = draftsForGroups([
      template.toJson(),
    ], groupReceipt(receipt, split: true));
    return receiptSurface(
      surfaceId: 'loc_rcpt_fm',
      receipt: receipt,
      drafts: [for (final d in drafts) EntryDraft.fromJson(d)],
      split: true,
    );
  },
  'nudge_bill': () => nudgeSurface(
    surfaceId: 'loc_nudge_internet',
    text: 'Internet is usually paid by the 5th.',
    kind: NudgeKind.bill,
    actionLabel: 'Add',
    action: const LocalAction(
      LocalActionNames.sendText,
      context: {'message': 'Paid the internet bill, 45 dollars'},
    ),
  ),
  'queued_offline': () => queuedSurface(
    surfaceId: 'loc_queue_q1',
    heard: const TranscriptData(text: 'Taxi home, 6,000 dinars', seconds: 3),
    text: "You're offline. This will be read when you're back online.",
    actionLabel: 'Retry',
    action: const LocalAction(
      LocalActionNames.retryQueued,
      context: {'captureId': 'q1'},
    ),
  ),
  'notice_limit': () => noticeSurface(
    surfaceId: 'loc_notice_limit',
    text: "You've used today's cloud answers. Typed entries still save.",
    kind: NoticeKind.limit,
    actionLabel: 'Add manually',
    action: const LocalAction(LocalActionNames.openManualForm),
  ),
  'saved_note': () =>
      savedSurface(surfaceId: 'loc_saved_two', text: 'Saved 2 entries.'),
};
