// WP-24: the daily rate prompt in Home's notice slot (ARCHITECTURE 3.5,
// D-16), with the clock injected: first open, already answered, answered
// by the partner, the next day, Same, Change and the >5% confirmation.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/features/home/home_providers.dart';
import 'package:xpense_app/features/home/home_screen.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'home_test_data.dart';

FxRate rate(String value) => FxRate.forPair(FxPair.usdIqd, value).valueOrNull!;

/// Lets a glass sheet or action sheet finish moving.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> typeKeys(WidgetTester tester, String keys) async {
  for (final key in keys.split('')) {
    await tester.tap(find.text(key).last);
    await tester.pump();
  }
}

Future<void> backspace(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.bySemanticsLabel('Delete').last);
    await tester.pump();
  }
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

void main() {
  const question = "Today's dollar rate?";
  final nudge = find.text('Spent something? Just say it.');

  testWidgets('first open of the day: the prompt with the last rate', (
    tester,
  ) async {
    final services = artboardServices(rateAnswered: false);
    await pumpHome(tester, services: services);

    final prompt = tester.widget<RatePrompt>(find.byType(RatePrompt));
    expect(prompt.question, question);
    expect(prompt.rate, '1,705');
    expect(
      prompt.semanticLabel,
      "Today's dollar rate? The last one was 1,705 dinars.",
    );
    expect(nudge, findsNothing, reason: 'the prompt takes the notice slot');
  });

  testWidgets('Same keeps the last rate for today, for both partners', (
    tester,
  ) async {
    final services = artboardServices(rateAnswered: false);
    await pumpHome(tester, services: services);

    await tester.tap(find.text('Same'));
    await tester.pumpAndSettle();

    final written = services.accounts.fx.written.single;
    expect(written.day, '2026-11-21');
    expect(written.rate.rateString, '1705');
    expect(written.enteredBy, you);
    expect(find.byType(RatePrompt), findsNothing);
    expect(nudge, findsOneWidget);
  });

  testWidgets('already answered today: no prompt', (tester) async {
    await pumpHome(tester, services: artboardServices());
    expect(find.byType(RatePrompt), findsNothing);
    expect(nudge, findsOneWidget);
  });

  testWidgets('the partner answers: the prompt goes, nothing is written', (
    tester,
  ) async {
    final services = artboardServices(rateAnswered: false);
    await pumpHome(tester, services: services);
    expect(find.byType(RatePrompt), findsOneWidget);

    services.accounts.fx.put(
      DailyRate(day: '2026-11-21', rate: rate('1710'), enteredBy: sam),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RatePrompt), findsNothing);
    expect(services.accounts.fx.written, isEmpty);
  });

  testWidgets('the next household day asks again', (tester) async {
    final services = artboardServices();
    await pumpHome(tester, services: services);
    expect(find.byType(RatePrompt), findsNothing);

    services.clock.now = DateTime(2026, 11, 22, 8);
    containerOf(tester).read(homeMonthProvider.notifier).refresh();
    await tester.pumpAndSettle();

    final prompt = tester.widget<RatePrompt>(find.byType(RatePrompt));
    // The rate "Same" keeps is the one entered yesterday.
    expect(prompt.rate, '1,705');
  });

  testWidgets('only a household with accounts in both currencies is asked', (
    tester,
  ) async {
    final services = artboardServices(rateAnswered: false);
    for (final a in services.accounts.allAccounts) {
      if (a.currency == Currency.iqd) {
        await services.accounts.setArchived(a.id, archived: true);
      }
    }
    await pumpHome(tester, services: services);
    expect(find.byType(RatePrompt), findsNothing);
    expect(nudge, findsOneWidget);
  });

  testWidgets('Change: a rate within 5% saves at once', (tester) async {
    final services = artboardServices(rateAnswered: false);
    await pumpHome(tester, services: services);

    await tester.tap(find.text('Change'));
    await settle(tester);
    expect(find.text("Today's dollar rate"), findsOneWidget);
    await backspace(tester, 2);
    await typeKeys(tester, '50');
    expect(find.text('1,750'), findsOneWidget);
    await tester.tap(find.text('Save').last);
    await settle(tester);

    expect(services.accounts.fx.written.single.rate.rateString, '1750');
    expect(find.byType(RatePrompt), findsNothing);
  });

  testWidgets('Change: a rate more than 5% away asks first', (tester) async {
    final services = artboardServices(rateAnswered: false);
    await pumpHome(tester, services: services);

    await tester.tap(find.text('Change'));
    await settle(tester);
    // A slip of the finger: 17,050 instead of 1,705.
    await typeKeys(tester, '0');
    await tester.tap(find.text('Save').last);
    await settle(tester);

    expect(
      find.text('17,050 is more than 5% away from 1,705. Is it right?'),
      findsOneWidget,
    );
    expect(services.accounts.fx.written, isEmpty);

    // Change it goes back to the keypad with what was typed.
    await tester.tap(find.text('Change it'));
    await settle(tester);
    expect(find.text('17,050'), findsOneWidget);
    await backspace(tester, 1);
    await tester.tap(find.text('Save').last);
    await settle(tester);
    expect(services.accounts.fx.written.single.rate.rateString, '1705');
  });

  testWidgets('a far-away rate can still be saved after confirming', (
    tester,
  ) async {
    final services = artboardServices(rateAnswered: false);
    await pumpHome(tester, services: services);

    await tester.tap(find.text('Change'));
    await settle(tester);
    await backspace(tester, 4);
    await typeKeys(tester, '1520');
    await tester.tap(find.text('Save').last);
    await settle(tester);
    expect(
      find.text('1,520 is more than 5% away from 1,705. Is it right?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Save 1,520'));
    await settle(tester);

    expect(services.accounts.fx.written.single.rate.rateString, '1520');
  });

  test('exactly 5% away saves without asking', () {
    expect(isRateJump(rate('1000'), rate('1050')), isFalse);
    expect(isRateJump(rate('1000'), rate('1050.1')), isTrue);
    expect(isRateJump(rate('1000'), rate('950')), isFalse);
    expect(isRateJump(rate('1000'), rate('949.9999')), isTrue);
  });

  testWidgets('a failed save keeps the prompt and says so', (tester) async {
    final services = artboardServices(rateAnswered: false);
    await pumpHome(tester, services: services);
    services.accounts.fx.nextFailure = const FxNotAllowed();

    await tester.tap(find.text('Same'));
    await tester.pumpAndSettle();

    expect(find.byType(RatePrompt), findsOneWidget);
    expect(find.text("Couldn't save the rate. Try again."), findsOneWidget);
  });

  testWidgets("the household's first rate: Enter opens an empty keypad", (
    tester,
  ) async {
    final services = artboardServices(rateAnswered: false);
    services.accounts.fx.clear();
    await pumpHome(tester, services: services);

    expect(find.text("What's today's dollar rate?"), findsOneWidget);
    await tester.tap(find.text('Enter'));
    await settle(tester);
    await typeKeys(tester, '1520');
    await tester.tap(find.text('Save').last);
    await settle(tester);

    // Nothing to compare with: no confirmation.
    expect(services.accounts.fx.written.single.rate.rateString, '1520');
  });

  test('dailyRateAsk', () {
    final rates = [
      DailyRate(day: '2026-11-20', rate: rate('1705')),
      DailyRate(day: '2026-11-18', rate: rate('1700')),
    ];
    const both = [Currency.usd, Currency.iqd];
    expect(
      dailyRateAsk(today: '2026-11-21', rates: rates, accountCurrencies: both),
      DailyRateAsk(today: '2026-11-21', previous: rates.first),
    );
    expect(
      dailyRateAsk(today: '2026-11-20', rates: rates, accountCurrencies: both),
      isNull,
    );
    expect(
      dailyRateAsk(
        today: '2026-11-21',
        rates: rates,
        accountCurrencies: const [Currency.usd],
      ),
      isNull,
    );
    expect(rateOnOrBefore(rates, '2026-11-19')?.day, '2026-11-18');
    expect(rateOnOrBefore(rates, '2026-11-17'), isNull);
  });
}
