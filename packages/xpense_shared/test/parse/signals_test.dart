import 'package:test/test.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'fixtures.dart';

typedef SignalCase = ({
  String text,
  int amounts,
  bool conj,
  bool question,
  bool command,
  bool person,
});

void main() {
  group('complexity signals (AI_PIPELINE 2)', () {
    final cases = <SignalCase>[
      // Single entries.
      (
        text: 'lunch 15000',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'bread and milk 5000',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'a coffee and a cake 4000',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'one and a half million for rent',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'also 5000 for taxi',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'paid 5000 for bread and milk',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      // Several entries.
      (
        text: 'salary 3,200 and rent 1,400',
        amounts: 2,
        conj: true,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'lunch 15000 and taxi 5000',
        amounts: 2,
        conj: true,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'paid rent and bought groceries 50',
        amounts: 1,
        conj: true,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: '15000 lunch plus 2000 tip',
        amounts: 2,
        conj: true,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'paid 5000 then 3000',
        amounts: 2,
        conj: true,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'lunch 15000, taxi 5000',
        amounts: 2,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'lunch 15000 & taxi 5000',
        amounts: 2,
        conj: true,
        question: false,
        command: false,
        person: false,
      ),
      // Questions.
      (
        text: 'how much did we spend on food this month?',
        amounts: 0,
        conj: false,
        question: true,
        command: false,
        person: false,
      ),
      (
        text: 'what did I spend yesterday',
        amounts: 0,
        conj: false,
        question: true,
        command: false,
        person: false,
      ),
      (
        text: 'which card did I use',
        amounts: 0,
        conj: false,
        question: true,
        command: false,
        person: false,
      ),
      (
        text: 'show my spending',
        amounts: 0,
        conj: false,
        question: true,
        command: false,
        person: false,
      ),
      (
        text: 'is rent paid',
        amounts: 0,
        conj: false,
        question: true,
        command: false,
        person: false,
      ),
      (
        text: '5000 for lunch?',
        amounts: 1,
        conj: false,
        question: true,
        command: false,
        person: false,
      ),
      (
        text: "what's my balance",
        amounts: 0,
        conj: false,
        question: true,
        command: false,
        person: false,
      ),
      // Commands.
      (
        text: 'delete the last one',
        amounts: 0,
        conj: false,
        question: false,
        command: true,
        person: false,
      ),
      (
        text: 'please undo that',
        amounts: 0,
        conj: false,
        question: false,
        command: true,
        person: false,
      ),
      (
        text: 'undo',
        amounts: 0,
        conj: false,
        question: false,
        command: true,
        person: false,
      ),
      (
        text: 'can you delete the taxi',
        amounts: 0,
        conj: false,
        question: false,
        command: true,
        person: false,
      ),
      (
        text: 'change the lunch to 15000',
        amounts: 1,
        conj: false,
        question: false,
        command: true,
        person: false,
      ),
      (
        text: 'set a budget of 500 for food',
        amounts: 1,
        conj: false,
        question: false,
        command: true,
        person: false,
      ),
      (
        text: 'new goal: trip 2000',
        amounts: 1,
        conj: false,
        question: false,
        command: true,
        person: false,
      ),
      (
        text: 'I want to create a goal for the car',
        amounts: 0,
        conj: false,
        question: false,
        command: true,
        person: false,
      ),
      // Person transfers.
      (
        text: 'gave Alex 300',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: true,
      ),
      (
        text: 'lent 300 dinars to Sara',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: true,
      ),
      (
        text: 'borrowed 500 from dad',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: true,
      ),
      (
        text: 'gave Omar 20000',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: true,
      ),
      (
        text: 'Sara owes me 10000',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: true,
      ),
      (
        text: 'sent mom 100 dollars',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: true,
      ),
      (
        text: 'Alex paid me back 50000',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: true,
      ),
      (
        text: 'gave the waiter 2000 tip',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'gave tip 2000',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: 'Lunch with Alex 15000',
        amounts: 1,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      // Nothing.
      (
        text: 'hello',
        amounts: 0,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
      (
        text: '',
        amounts: 0,
        conj: false,
        question: false,
        command: false,
        person: false,
      ),
    ];
    for (final c in cases) {
      test('"${c.text}"', () {
        final s = parseText(c.text, iqdHome()).signals;
        expect(
          (
            s.amountCount,
            s.hasConjunction,
            s.isQuestion,
            s.isCommand,
            s.hasPersonTransfer,
          ),
          (c.amounts, c.conj, c.question, c.command, c.person),
        );
      });
    }

    for (final a in Attachment.values) {
      test('attachment ${a.wire} is passed through', () {
        final s = parseText('receipt', iqdHome(attachment: a)).signals;
        expect(s.attachment, a);
        expect(s.toSchema().attachment, a.wire);
      });
    }
  });

  group('unresolved fields and intent cues', () {
    final cases = <({String text, List<String> unresolved, String? cue})>[
      (
        text: 'taxi 5000',
        unresolved: ['category', 'account', 'intent'],
        cue: null,
      ),
      (
        text: 'spent 5000 on taxi',
        unresolved: ['category', 'account'],
        cue: 'expense',
      ),
      (
        text: 'paid 300 for rent',
        unresolved: ['category', 'account'],
        cue: 'expense',
      ),
      (text: 'paid Alex 300', unresolved: ['category', 'intent'], cue: null),
      (text: 'gave Alex 300', unresolved: ['category', 'intent'], cue: null),
      (
        text: 'lent 300 dinars to Sara',
        unresolved: ['account'],
        cue: 'loan_given',
      ),
      (
        text: 'borrowed 500 from dad',
        unresolved: ['account'],
        cue: 'loan_taken',
      ),
      (
        text: 'Alex paid me back 50000',
        unresolved: [],
        cue: 'repayment_received',
      ),
      (
        text: 'I paid back Sara 100 dollars',
        unresolved: ['account'],
        cue: 'repayment_made',
      ),
      (
        text: 'earned 500 freelance',
        unresolved: ['category', 'account'],
        cue: 'income',
      ),
      (
        text: 'got paid 1200',
        unresolved: ['category', 'account'],
        cue: 'income',
      ),
      (
        text: 'transferred 100 to Rafidain bank',
        unresolved: [],
        cue: 'transfer',
      ),
      (text: 'saved 200 to trip fund', unresolved: [], cue: 'savings_move'),
      (
        text: 'opening balance 500000',
        unresolved: ['account'],
        cue: 'adjustment',
      ),
      (
        text: 'spent 5000 and lent 2000',
        unresolved: ['category', 'account', 'intent'],
        cue: null,
      ),
      (
        text: 'how much did we spend',
        unresolved: ['category', 'account', 'intent'],
        cue: null,
      ),
      (text: 'paid with visa 30', unresolved: ['category'], cue: 'expense'),
      // A merchant rule settles category and account; the category's kind
      // settles the intent.
      (text: '42.80 at Costco', unresolved: [], cue: null),
      // A rule that sets the intent.
      (text: 'carrefour 18000', unresolved: ['account'], cue: null),
      // A rule category the parser does not know gives no kind.
      (text: 'generator 25000', unresolved: ['account', 'intent'], cue: null),
    ];
    for (final c in cases) {
      test('"${c.text}" → ${c.unresolved}', () {
        final result = parseText(c.text, iqdHome());
        expect(result.signals.toSchema().unresolved, c.unresolved);
        expect(result.intentCue?.wire, c.cue);
      });
    }

    test('a one-account household has its account settled', () {
      final context = ParseContext(
        clock: iqdHome().clock,
        accounts: [fixtureAccounts.first],
        defaultAccountId: 'acc_cash',
      );
      final s = parseText('spent 5000', context).signals;
      expect(s.unresolved, [UnresolvedField.category]);
    });
  });
}
