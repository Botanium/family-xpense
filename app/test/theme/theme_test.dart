import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/theme/theme.dart';

void main() {
  group('buildAppTheme', () {
    for (final brightness in Brightness.values) {
      for (final highContrast in [false, true]) {
        final label =
            '${brightness.name}${highContrast ? ', high contrast' : ''}';
        test('$label attaches every Signal extension', () {
          final theme = buildAppTheme(brightness, highContrast: highContrast);
          expect(theme.extension<XpColors>(), isNotNull);
          expect(theme.extension<XpType>(), isNotNull);
          expect(theme.extension<XpGlass>(), isNotNull);
          expect(theme.extension<XpElevation>(), isNotNull);
          expect(theme.brightness, brightness);
          expect(theme.colorScheme.brightness, brightness);
        });
      }
    }

    test('hand-authors the colour scheme from the slots (never fromSeed)', () {
      final light = buildAppTheme(Brightness.light).colorScheme;
      expect(light.primary, XpColors.light.primaryFill);
      expect(light.onPrimary, XpColors.light.onPrimaryFill);
      expect(light.surface, XpColors.light.surface);
      expect(light.onSurface, XpColors.light.ink);
      expect(light.error, XpColors.light.danger);
      final dark = buildAppTheme(Brightness.dark).colorScheme;
      expect(dark.primary, XpColors.dark.primaryFill);
      expect(dark.surface, XpColors.dark.surface);
    });

    test('orange is never the primary colour', () {
      for (final b in Brightness.values) {
        final scheme = buildAppTheme(b).colorScheme;
        expect(scheme.primary, isNot(XpColors.light.accent));
        expect(scheme.secondary, isNot(XpColors.light.accent));
      }
    });

    test('canvas is the scaffold background', () {
      expect(
        buildAppTheme(Brightness.dark).scaffoldBackgroundColor,
        XpColors.dark.canvas,
      );
    });

    test('theme changes cut rather than animate', () {
      expect(xpThemeAnimationStyle, AnimationStyle.noAnimation);
      expect(XpColors.light.lerp(XpColors.dark, 0.4), same(XpColors.light));
      expect(XpColors.light.lerp(XpColors.dark, 0.6), same(XpColors.dark));
    });
  });

  group('colour slots', () {
    test('Increase Contrast darkens secondary ink and doubles hairlines', () {
      expect(XpColors.lightHighContrast.inkSecondary.toARGB32(), 0xFF4A4944);
      expect(XpColors.darkHighContrast.inkSecondary.toARGB32(), 0xFFC9C7BF);
      expect(XpColors.lightHighContrast.hairlineWeight, 2);
      expect(XpColors.light.hairlineWeight, 1);
    });

    test('values match DESIGN_SYSTEM 3.1', () {
      const l = XpColors.light;
      expect(l.canvas.toARGB32(), 0xFFECEBE7);
      expect(l.surface.toARGB32(), 0xFFFAF9F6);
      expect(l.ink.toARGB32(), 0xFF0B0B0C);
      expect(l.inkSecondary.toARGB32(), 0xFF67665F);
      expect(l.inkTertiary.toARGB32(), 0xFF7A7871);
      expect(l.accent.toARGB32(), 0xFFFF5B1A);
      expect(l.tabInactive.toARGB32(), 0xFF3F3E3A);
      const d = XpColors.dark;
      expect(d.canvas.toARGB32(), 0xFF161617);
      expect(d.surface.toARGB32(), 0xFF1F1F21);
      expect(d.ink.toARGB32(), 0xFFF2F1ED);
      expect(d.tabInactive.toARGB32(), 0xFFB4B2AA);
    });

    test('category keys resolve, unknown keys fall back to secondary ink', () {
      expect(XpColors.light.category('cat1'), XpColors.light.categories[0]);
      expect(XpColors.dark.category('cat8'), XpColors.dark.categories[7]);
      expect(XpColors.light.category('cat9'), XpColors.light.inkSecondary);
      expect(XpColors.light.category('red'), XpColors.light.inkSecondary);
      expect(XpColors.light.categories, hasLength(8));
      expect(XpColors.dark.categories, hasLength(8));
    });
  });

  group('type', () {
    final type = XpType.from(XpColors.light);

    test('figures are Geist Mono with tabular digits', () {
      for (final style in [
        type.figureHero,
        type.figureLarge,
        type.figureMedium,
        type.figureBody,
        type.figureSmall,
        type.monoLabel,
        type.screenTitle,
      ]) {
        expect(style.fontFamily, XpFonts.mono);
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
    });

    test('sizes and line heights follow DESIGN_SYSTEM 4', () {
      void check(TextStyle s, double size, double line, FontWeight w) {
        expect(s.fontSize, size);
        expect(s.height! * size, closeTo(line, 0.001));
        expect(s.fontWeight, w);
      }

      check(type.figureHero, 50, 56, FontWeight.w300);
      check(type.figureLarge, 38, 42, FontWeight.w300);
      check(type.figureMedium, 28, 32, FontWeight.w300);
      check(type.monoLabel, 11, 14, FontWeight.w400);
      check(type.quote, 20, 27, FontWeight.w500);
      check(type.title, 16, 22, FontWeight.w600);
      check(type.body, 15, 22, FontWeight.w400);
      check(type.tabLabelActive, 11, 13, FontWeight.w600);
      expect(type.figureHero.letterSpacing, -2.5);
    });
  });

  group('motion', () {
    testWidgets('Reduce Motion resolves every duration to zero', (
      tester,
    ) async {
      late XpMotion motion;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              motion = XpMotion.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(motion.isReduced, isTrue);
      expect(motion.fast, Duration.zero);
      expect(motion.slow, Duration.zero);
      expect(motion.count, Duration.zero);
      expect(XpMotion.standard.base, const Duration(milliseconds: 220));
    });

    test('spring curve starts at 0 and ends at 1', () {
      expect(XpMotion.slowCurve.transform(0), 0);
      expect(XpMotion.slowCurve.transform(1), 1);
    });
  });

  group('fonts', () {
    test('Geist and Geist Mono are bundled in the weights the type uses', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final file in [
        'assets/fonts/geist/Geist-Regular.ttf',
        'assets/fonts/geist/Geist-Medium.ttf',
        'assets/fonts/geist/Geist-SemiBold.ttf',
        'assets/fonts/geist_mono/GeistMono-Light.ttf',
        'assets/fonts/geist_mono/GeistMono-Regular.ttf',
        'assets/fonts/geist_mono/GeistMono-Medium.ttf',
      ]) {
        expect(File(file).existsSync(), isTrue, reason: file);
        expect(pubspec, contains(file));
      }
      expect(pubspec, contains('family: ${XpFonts.sans}'));
      expect(pubspec, contains('family: ${XpFonts.mono}'));
      expect(pubspec, isNot(contains('google_fonts')));
    });

    testWidgets('the OFL licence is registered', (tester) async {
      registerFontLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      final geist = entries.where((e) => e.packages.contains('Geist'));
      expect(geist, isNotEmpty);
      expect(
        geist.first.paragraphs.map((p) => p.text).join(' '),
        contains('SIL Open Font License'),
      );
    });
  });
}
