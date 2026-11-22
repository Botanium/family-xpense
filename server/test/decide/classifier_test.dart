import 'package:test/test.dart';
import 'package:xpense_agent/auth/xpense_context.dart';
import 'package:xpense_agent/decide/classifier.dart';
import 'package:xpense_shared/xpense_shared.dart';

const _context = XpenseContext(
  uid: 'u1',
  hid: 'h1',
  locale: 'en',
  privacyMode: PrivacyMode.smart,
  tz: 'Asia/Baghdad',
);

void main() {
  test('question keys match the shared wire keys', () {
    expect(
      DecideQuestion.values.map((q) => q.key),
      orderedEquals(decideQuestionKeys),
    );
    for (final q in DecideQuestion.values) {
      expect(DecideQuestion.byKey(q.key), q);
    }
    expect(DecideQuestion.byKey('nope'), isNull);
  });

  test('the fake is unavailable by default and records calls', () async {
    final fake = FakeEntryClassifier();
    final response = await fake.classify(
      context: _context,
      text: 'Lunch 15,000',
      ask: {DecideQuestion.intent, DecideQuestion.category},
      parsed: DecideParsed(amountMinor: 15000, currency: 'IQD'),
    );
    expect(response.unavailable, isTrue);
    expect(fake.calls.single.text, 'Lunch 15,000');
    expect(fake.calls.single.ask, contains(DecideQuestion.category));
  });

  test('the fake answers with a fixed response', () async {
    final fake = FakeEntryClassifier.always(
      DecideResponse(
        intent: ChoiceAnswer(choice: 'expense', confidence: 0.97),
        calibrated: true,
      ),
    );
    final response = await fake.classify(
      context: _context,
      text: 'x',
      ask: {DecideQuestion.intent},
    );
    expect(response.intent?.choice, 'expense');
  });
}
