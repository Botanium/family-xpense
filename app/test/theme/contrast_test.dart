// Every declared foreground and background pair of DESIGN_SYSTEM 3.2, in
// both themes and both contrast settings, computed with
// Color.computeLuminance().
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/theme/theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Text: 4.5:1. Large figures and graphics (dots, bars): 3:1.
const double text = 4.5;
const double large = 3;

typedef Pair = (String name, Color fg, Color bg, double needs);

List<Pair> pairsFor(XpColors c) => [
  ('ink on canvas', c.ink, c.canvas, text),
  ('ink on surface', c.ink, c.surface, text),
  ('ink on sunken', c.ink, c.surfaceSunken, text),
  ('inkSecondary on canvas', c.inkSecondary, c.canvas, text),
  ('inkSecondary on surface', c.inkSecondary, c.surface, text),
  ('inkSecondary on sunken', c.inkSecondary, c.surfaceSunken, text),
  (
    'inkTertiary on canvas (large figures only)',
    c.inkTertiary,
    c.canvas,
    large,
  ),
  ('inkOnAccent on accent', c.inkOnAccent, c.accent, text),
  ('income on canvas', c.income, c.canvas, text),
  ('income on surface', c.income, c.surface, text),
  ('danger on canvas', c.danger, c.canvas, text),
  ('danger on surface', c.danger, c.surface, text),
  ('saved dot on canvas', c.saved, c.canvas, large),
  ('loan dot on canvas', c.loan, c.canvas, large),
  ('onPrimaryFill on primaryFill', c.onPrimaryFill, c.primaryFill, text),
  ('onSelectedFill on selectedFill', c.onSelectedFill, c.selectedFill, text),
  ('tabInactive on canvas', c.tabInactive, c.canvas, text),
  ('receiptInk on receiptPaper', c.receiptInk, c.receiptPaper, text),
  ('onMedia on scanBackdrop', c.onMedia, c.scanBackdrop, text),
  ('primary button fill on canvas (shape)', c.primaryFill, c.canvas, large),
  ('switch on-track on canvas (shape)', c.selectedFill, c.canvas, large),
  ('switch knob on on-track', c.onSelectedFill, c.selectedFill, large),
  for (final (i, cat) in c.categories.indexed) ...[
    ('cat${i + 1} on canvas', cat, c.canvas, large),
    ('cat${i + 1} on surface', cat, c.surface, large),
  ],
];

void main() {
  final themes = {
    'light': XpColors.light,
    'dark': XpColors.dark,
    'light, Increase Contrast': XpColors.lightHighContrast,
    'dark, Increase Contrast': XpColors.darkHighContrast,
  };

  for (final MapEntry(key: theme, value: colors) in themes.entries) {
    group('$theme theme', () {
      for (final (name, fg, bg, needs) in pairsFor(colors)) {
        test('$name ≥ $needs:1', () {
          final ratio = contrast(fg, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(needs),
            reason: '$name is ${ratio.toStringAsFixed(2)}:1',
          );
        });
      }
    });
  }

  group('documented ratios (DESIGN_SYSTEM 3.2)', () {
    void near(Color a, Color b, double expected) =>
        expect(contrast(a, b), closeTo(expected, 0.15));

    test('match the table', () {
      const l = XpColors.light;
      const d = XpColors.dark;
      near(l.ink, l.canvas, 16.6);
      near(l.inkSecondary, l.canvas, 4.8);
      near(l.inkTertiary, l.canvas, 3.7);
      near(l.income, l.canvas, 5.1);
      near(l.income, l.surface, 5.8);
      near(l.inkOnAccent, l.accent, 6.3);
      near(l.saved, l.canvas, 4.4);
      near(l.loan, l.canvas, 4.3);
      near(d.ink, d.canvas, 16);
      near(d.inkSecondary, d.canvas, 7);
      near(d.income, d.canvas, 8.2);
    });

    test('orange fails as text, so it is never text', () {
      expect(
        contrast(XpColors.light.accent, XpColors.light.canvas),
        lessThan(text),
      );
    });
  });

  group('glass composites (iOS review item 6)', () {
    Color over(Color tint, Color under) => Color.alphaBlend(tint, under);

    test('light: inactive tab label over the 72 % control glass above ink '
        'content (worst case) stays ≥ 4.5:1', () {
      final tint = XpGlass.light.recipe(GlassVariant.control).tint;
      expect(tint.a, closeTo(0.72, 0.005));
      final composite = over(tint, XpColors.light.ink);
      expect(
        contrast(XpColors.light.tabInactive, composite),
        greaterThanOrEqualTo(text),
      );
      expect(
        contrast(XpColors.light.ink, composite),
        greaterThanOrEqualTo(text),
      );
    });

    test("light: the prototype's 60 % tint fails that case, which is why it "
        'rose', () {
      final tint = XpGlass.light
          .recipe(GlassVariant.control)
          .tint
          .withValues(alpha: 0.6);
      final composite = over(tint, XpColors.light.ink);
      expect(contrast(XpColors.light.tabInactive, composite), lessThan(text));
    });

    test('dark: inactive tab label over the control glass above canvas '
        'content stays ≥ 4.5:1', () {
      final tint = XpGlass.dark.recipe(GlassVariant.control).tint;
      final composite = over(tint, XpColors.dark.canvas);
      expect(
        contrast(XpColors.dark.tabInactive, composite),
        greaterThanOrEqualTo(text),
      );
    });

    // Known gap, escalated in the WP-03 PR: at the specified 64 % tint, the
    // dark tab bar over light ink content (a figure scrolled under it)
    // composites to about 2.4:1. 84 % would pass. Recorded here so a change
    // to the dark tint shows up in review.
    test('dark: worst case over ink content is documented, not yet fixed', () {
      final tint = XpGlass.dark.recipe(GlassVariant.control).tint;
      final composite = over(tint, XpColors.dark.ink);
      final ratio = contrast(XpColors.dark.tabInactive, composite);
      expect(ratio, closeTo(2.44, 0.1));
      final fixed = over(tint.withValues(alpha: 0.84), XpColors.dark.ink);
      expect(
        contrast(XpColors.dark.tabInactive, fixed),
        greaterThanOrEqualTo(text),
      );
    });

    test('Increase Contrast glass keeps ink text ≥ 4.5:1 over ink content', () {
      for (final colors in [
        XpColors.lightHighContrast,
        XpColors.darkHighContrast,
      ]) {
        final glass = colors.brightness == Brightness.light
            ? XpGlass.light
            : XpGlass.dark;
        final recipe = glass
            .recipe(GlassVariant.control)
            .increasedContrast(colors.ink);
        final composite = over(recipe.tint, colors.ink);
        expect(
          contrast(colors.tabInactive, composite),
          greaterThanOrEqualTo(text),
        );
      }
    });

    test('on-device chip text (income) on button glass over canvas', () {
      for (final (colors, glass) in [
        (XpColors.light, XpGlass.light),
        (XpColors.dark, XpGlass.dark),
      ]) {
        final composite = over(
          glass.recipe(GlassVariant.button).tint,
          colors.canvas,
        );
        expect(contrast(colors.income, composite), greaterThanOrEqualTo(text));
      }
    });
  });
}
