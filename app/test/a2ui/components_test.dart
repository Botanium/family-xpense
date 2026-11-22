// The simpler catalog components through the host: money formatting,
// restricted Markdown, inputs with checks, and local actions of lists and
// cards (A2UI_CATALOG 3, story S3.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/restricted_markdown.dart';
import 'package:xpense_shared/xpense_shared.dart';

import 'a2ui_harness.dart';

Map<String, Object?> _surface(
  List<Map<String, Object?>> components, [
  Map<String, Object?>? dataModel,
]) => {
  'version': '1.0',
  'createSurface': {
    'surfaceId': 'probe',
    'catalogId': xpenseCatalogId,
    'components': components,
    'dataModel': ?dataModel,
  },
};

Map<String, Object?> _money(int minor, String currency, [Object? approx]) =>
    _surface([
      {
        'id': 'root',
        'component': 'MoneyText',
        'amountMinor': minor,
        'currency': currency,
        'approx': ?approx,
      },
    ]);

void main() {
  group('MoneyText', () {
    testWidgets('decimals come from the currency, never a fixed 100', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith([_money(10000, 'IQD')]);
      await pumpThread(tester, host);
      expect(find.text('IQD 10,000'), findsOneWidget);

      final usd = hostWith([_money(10000, 'USD')]);
      await pumpThread(tester, usd.host);
      expect(find.text('USD 100.00'), findsOneWidget);
    });

    testWidgets('an unknown currency shows a dash, not a guess', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith([_money(10000, 'EUR')]);
      await pumpThread(tester, host);
      expect(find.text('EUR —'), findsOneWidget);
      expect(find.textContaining('100'), findsNothing);
    });

    testWidgets('approx shows the converted amount beneath', (tester) async {
      final (:host, :actions, :sent) = hostWith([
        _money(10000, 'IQD', {'amountMinor': 587, 'currency': 'USD'}),
      ]);
      await pumpThread(tester, host);
      expect(find.text('≈ USD 5.87'), findsOneWidget);
    });
  });

  group('Text: restricted Markdown', () {
    test('headings, paragraphs and lists', () {
      final blocks = parseBlocks('## Title\nOne\ntwo\n\n- a\n1. b');
      expect(blocks[0], isA<HeadingBlock>());
      expect((blocks[1] as ParagraphBlock).text, 'One two');
      expect((blocks[2] as ListItemBlock).marker, '•');
      expect((blocks[3] as ListItemBlock).marker, '1.');
    });

    test('links, images and code are words only', () {
      String plain(String s) =>
          inlineSpans(s).map((span) => (span as TextSpan).text).join();
      expect(plain('see [the bank](https://evil.example)'), 'see the bank');
      expect(plain('![receipt](https://evil.example/x.png)'), 'receipt');
      expect(plain('run `rm -rf`'), 'run rm -rf');
      expect(plain('acc_chk_main stays'), 'acc_chk_main stays');
    });

    test('bold and italic are styled', () {
      final spans = inlineSpans('a **b** *c*').cast<TextSpan>();
      expect(spans.map((s) => s.text), ['a ', 'b', ' ', 'c']);
      expect(spans.elementAt(1).style?.fontWeight, FontWeight.w600);
      expect(spans.elementAt(3).style?.fontStyle, FontStyle.italic);
    });

    testWidgets('a ## line renders as a section label', (tester) async {
      final (:host, :actions, :sent) = hostWith([
        _surface([
          {
            'id': 'root',
            'component': 'Text',
            'text': '## Food\nIt was **fine**',
          },
        ]),
      ]);
      await pumpThread(tester, host);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('It was fine', findRichText: true), findsOneWidget);
    });
  });

  group('inputs', () {
    testWidgets('TextField writes its path; a failed check shows once typed', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_refine_form'));
      await pumpThread(tester, host);
      expect(find.text('Say a few words'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'split with my sister');
      await tester.pump();
      expect(
        host.debugDataModel('ref_note', '/answer/note'),
        'split with my sister',
      );
      expect(find.text('Say a few words'), findsNothing);
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(sent.single.name, 'xp.refine');
      expect(sent.single.context['note'], 'split with my sister');
    });
  });

  group('local actions of lists and cards', () {
    testWidgets('SuggestionChips send their message as the next capture', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_analytics_answer'),
      );
      await pumpThread(tester, host);
      await tester.tap(find.text('By week'));
      expect(actions.calls.single, (
        method: 'sendText',
        argument: 'Show food spending by week this month',
      ));
      expect(sent, isEmpty);
    });

    testWidgets('SuggestionChips are disabled while a turn streams', (
      tester,
    ) async {
      final (:host, :actions, :sent) = hostWith(
        fixture('agent_analytics_answer'),
      );
      host.turnInProgress = true;
      await pumpThread(tester, host);
      await tester.tap(find.text('By week'));
      expect(actions.calls, isEmpty);
    });

    testWidgets('rows and cards open on the phone', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture('agent_loans_goals'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Lunch with the kids'));
      await tester.tap(find.text('Record a repayment'));
      await tester.tap(find.text('Holiday'));
      expect(actions.calls, [
        (method: 'openTransaction', argument: 't_101'),
        (method: 'openLoan', argument: 'loan_7'),
        (method: 'openGoal', argument: 'goal_2'),
      ]);
      expect(sent, isEmpty);
    });

    testWidgets('a local Notice action opens the manual form', (tester) async {
      final (:host, :actions, :sent) = hostWith(fixture('local_notice_limit'));
      await pumpThread(tester, host);
      await tester.tap(find.text('Add manually'));
      expect(actions.methods, ['openManualForm']);
    });
  });
}
