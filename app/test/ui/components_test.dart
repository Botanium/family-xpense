import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/gallery/gallery_entries.dart';
import 'package:xpense_app/core/ui/gallery/gallery_page.dart';
import 'package:xpense_app/core/ui/ui.dart';

import 'ui_harness.dart';

void main() {
  setUpAll(loadSignalFonts);

  group('MoneyFormat', () {
    test('splits by the currency exponent, never a hard-coded 100', () {
      final usd = MoneyFormat.figure(1248000, exponent: 2, currency: 'USD');
      expect(usd.whole, '12,480');
      expect(usd.fraction, '.00');
      expect(usd.withCurrency, 'USD 12,480.00');
      final iqd = MoneyFormat.figure(10000, exponent: 0, currency: 'IQD');
      expect(iqd.withCurrency, 'IQD 10,000');
      final three = MoneyFormat.figure(1234567, exponent: 3);
      expect(three.amount, '1,234.567');
    });

    test('signs: minus always, plus when asked', () {
      expect(
        MoneyFormat.figure(-4280, exponent: 2).amount,
        '−4,280'.replaceFirst('4,280', '42.80'),
      );
      expect(
        MoneyFormat.figure(320000, exponent: 2, signed: true).amount,
        '+3,200.00',
      );
      expect(MoneyFormat.figure(0, exponent: 2, signed: true).amount, '0.00');
      expect(MoneyFormat.figure(5, exponent: 2).amount, '0.05');
    });

    test('compact notation rounds half up and drops .0', () {
      expect(MoneyFormat.compact(16300000, exponent: 0).whole, '16.3M');
      expect(MoneyFormat.compact(16350000, exponent: 0).whole, '16.4M');
      expect(MoneyFormat.compact(2000000000, exponent: 0).whole, '2B');
      expect(MoneyFormat.compact(1500, exponent: 0).whole, '1.5K');
      expect(MoneyFormat.compact(999, exponent: 0).whole, '999');
      expect(MoneyFormat.compact(1248000, exponent: 2).whole, '12.5K');
    });

    test('parses typed text into minor units without doubles', () {
      expect(MoneyFormat.parseMinor('1,705', exponent: 0), 1705);
      expect(MoneyFormat.parseMinor('7.6', exponent: 2), 760);
      expect(MoneyFormat.parseMinor('7.63', exponent: 2), 763);
      expect(MoneyFormat.parseMinor('7.634', exponent: 2), isNull);
      expect(MoneyFormat.parseMinor('7.5', exponent: 0), isNull);
      expect(MoneyFormat.parseMinor('abc', exponent: 2), isNull);
      expect(MoneyFormat.parseMinor('', exponent: 2), isNull);
    });
  });

  group('HeroBalance', () {
    testWidgets('steps down to large, then compact, never truncating', (
      tester,
    ) async {
      Future<String> shown(double width) async {
        await tester.pumpWidget(
          signalHarness(
            width: width,
            child: const HeroBalance(
              label: 'Balance',
              minorUnits: 163450000,
              exponent: 0,
              currencyMark: 'IQD',
            ),
          ),
        );
        final rich = tester.widget<RichText>(
          find.descendant(
            of: find.byType(HeroBalance),
            matching: find.byWidgetPredicate(
              (w) => w is RichText && w.text.toPlainText().contains('IQD'),
            ),
          ),
        );
        final span = (rich.text as TextSpan).children!.first as TextSpan;
        return '${span.style!.fontSize}:${span.toPlainText()}';
      }

      expect(await shown(390), startsWith('50.0:'));
      expect(await shown(300), startsWith('38.0:'));
      expect(await shown(200), allOf(startsWith('38.0:'), contains('163.5M')));
    });
  });

  group('semantics and targets', () {
    testWidgets('every tappable gallery control is at least 44 × 44', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390, 1600) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      for (final entry in galleryEntries) {
        await tester.pumpWidget(
          signalHarness(child: GalleryEntryView(entry: entry)),
        );
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      }
      handle.dispose();
    });

    testWidgets('icon-only buttons carry labels', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        signalHarness(
          child: Row(
            children: [
              GlassIconButton(
                glyph: XpGlyph.back,
                semanticLabel: 'Back to home',
                onPressed: () {},
              ),
              AskButton(
                semanticLabel: 'Ask: talk, type or scan',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('Back to home'), findsOneWidget);
      expect(find.bySemanticsLabel('Ask: talk, type or scan'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('chips announce their selected state', (tester) async {
      final handle = tester.ensureSemantics();
      String? picked;
      await tester.pumpWidget(
        signalHarness(
          child: StatefulBuilder(
            builder: (context, setState) => ChoiceChips<String>(
              options: const [
                ChoiceOption(value: 'a', label: 'Cash'),
                ChoiceOption(value: 'b', label: 'Card'),
              ],
              selected: picked,
              onSelected: (v) => setState(() => picked = v),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Card'));
      await tester.pump();
      expect(picked, 'b');
      expect(
        tester.getSemantics(find.text('Card')),
        matchesSemantics(
          label: 'Card',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('the switch is a toggle with a label', (tester) async {
      final handle = tester.ensureSemantics();
      var value = false;
      await tester.pumpWidget(
        signalHarness(
          child: StatefulBuilder(
            builder: (context, setState) => XpSwitch(
              value: value,
              semanticLabel: 'Split by category',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(XpSwitch));
      await tester.pump();
      expect(value, isTrue);
      final node = tester.getSemantics(find.byType(XpSwitch));
      expect(node.label, 'Split by category');
      expect(node.flagsCollection.isToggled, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('tab bar items are selectable buttons with full labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var index = 0;
      await tester.pumpWidget(
        signalHarness(
          textScale: 3,
          child: StatefulBuilder(
            builder: (context, setState) => XpTabBar(
              items: const [
                XpTabItem(glyph: XpGlyph.home, label: 'Home'),
                XpTabItem(glyph: XpGlyph.activity, label: 'Activity'),
                XpTabItem(glyph: XpGlyph.goals, label: 'Goals'),
                XpTabItem(glyph: XpGlyph.accounts, label: 'Accounts'),
              ],
              selectedIndex: index,
              onSelected: (i) => setState(() => index = i),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Goals'));
      await tester.pump();
      expect(index, 2);
      final goals = tester.getSemantics(find.bySemanticsLabel('Goals'));
      expect(goals.flagsCollection.isSelected, Tristate.isTrue);
      handle.dispose();
    });

    testWidgets('charts speak their summary', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        signalHarness(
          child: const MiniBars(values: [1, 2, 3], summary: 'Spending summary'),
        ),
      );
      expect(find.bySemanticsLabel('Spending summary'), findsOneWidget);
      handle.dispose();
    });
  });

  group('RateChangeSheet', () {
    Widget sheet({String initial = '1,705', ValueChanged<String>? onSave}) =>
        signalHarness(
          child: RateChangeSheet(
            title: 'Rate',
            initial: initial,
            unit: 'IQD per USD',
            saveLabel: 'Save',
            backspaceLabel: 'Delete',
            onSave: onSave ?? (_) {},
          ),
        );

    Future<void> press(WidgetTester tester, String key, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.bySemanticsLabel(key).last);
        await tester.pump();
      }
    }

    testWidgets('caps whole digits at 6 and decimals at 4', (tester) async {
      String? saved;
      await tester.pumpWidget(sheet(onSave: (v) => saved = v));
      await press(tester, '9', times: 30);
      expect(tester.takeException(), isNull);
      expect(find.text('170,599'), findsOneWidget);
      await press(tester, '.');
      await press(tester, '5', times: 10);
      expect(tester.takeException(), isNull);
      expect(find.text('170,599.5555'), findsOneWidget);
      await tester.tap(find.text('Save'));
      expect(saved, '170599.5555');
    });

    testWidgets('an oversized initial value is bounded, not parsed', (
      tester,
    ) async {
      await tester.pumpWidget(
        sheet(initial: '123456789012345678901234567890.123456789'),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('123,456.1234'), findsOneWidget);
    });
  });

  group('large text', () {
    testWidgets(
      'rows stack the figure under the label at accessibility sizes',
      (tester) async {
        await tester.pumpWidget(
          signalHarness(
            textScale: 2,
            child: const LedgerRow(label: 'Income', value: '5,650.00'),
          ),
        );
        final label = tester.getTopLeft(find.text('Income'));
        final value = tester.getTopLeft(find.text('5,650.00'));
        expect(value.dy, greaterThan(label.dy));
        expect(value.dx, label.dx);
      },
    );

    testWidgets('the gallery lays out without overflow at 2× text', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(390, 1600) * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (final entry in galleryEntries) {
        await tester.pumpWidget(
          signalHarness(textScale: 2, child: GalleryEntryView(entry: entry)),
        );
        final error = tester.takeException();
        expect(error, isNull, reason: '${entry.name}: $error');
      }
    });
  });

  group('gallery', () {
    testWidgets('covers every component in DESIGN_SYSTEM 8', (tester) async {
      await tester.pumpWidget(signalHarness(child: const SizedBox()));
      final names = galleryEntries.map((e) => e.name).toSet();
      expect(names, hasLength(galleryEntries.length), reason: 'unique names');
      for (final required in [
        'top_bar',
        'tab_bar',
        'capture_dock_voice',
        'capture_dock_type',
        'search_field',
        'list_section',
        'ledger_rows',
        'slip',
        'disclosure',
        'buttons',
        'menu',
        'filter_bar',
        'switch',
        'system_sheets',
        'text_field',
        'amount_field',
        'progress',
        'glass_sheet',
        'context_menu',
        'badges',
        'money_text',
        'hero_balance',
        'mini_bars',
        'entry_slip',
        'choice_chips',
        'transcript_quote',
        'waveform',
        'glass_buttons',
        'nudge_row',
        'avatar_pair',
        'receipt_sheet',
        'undo_toast',
        'empty_state',
        'offline_banner',
        'rate_prompt',
        'rate_change_sheet',
        'lock_overlay',
        'goal_bar',
        'history_row',
        'skeleton',
      ]) {
        expect(names, contains(required));
      }
    });

    testWidgets('the gallery page builds and its tier pill cycles tiers', (
      tester,
    ) async {
      await tester.pumpWidget(
        signalHarness(child: const SizedBox(height: 900, child: GalleryPage())),
      );
      expect(find.text('GALLERY'), findsOneWidget);
      await tester.tap(find.textContaining('TIER'));
      await tester.pump();
      expect(find.textContaining('TIER 3 PREMIUM'), findsOneWidget);
      expect(galleryRoutePath, '/gallery');
    });
  });
}
