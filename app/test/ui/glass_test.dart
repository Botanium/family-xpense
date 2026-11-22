// GlassSurface (S0.7): six variants, four tiers, Reduce Transparency through
// the platform channel, Increase Contrast; goldens for tiers 0 and 1.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/gallery/gallery_entries.dart';
import 'package:xpense_app/core/ui/ui.dart';

import 'ui_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlassTierPolicy', () {
    test('household phones and newer start at premium (provisional)', () {
      expect(GlassTierPolicy.initialTierFor('iPhone16,2'), GlassTier.premium);
      expect(GlassTierPolicy.initialTierFor('iPhone18,1'), GlassTier.premium);
      expect(GlassTierPolicy.initialTierFor('iPhone17,3'), GlassTier.premium);
    });

    test('other recent iPhones start at standard, older at blur', () {
      expect(GlassTierPolicy.initialTierFor('iPhone15,4'), GlassTier.standard);
      expect(GlassTierPolicy.initialTierFor('iPhone14,5'), GlassTier.standard);
      expect(GlassTierPolicy.initialTierFor('iPhone13,2'), GlassTier.blur);
      expect(GlassTierPolicy.initialTierFor('iPhone10,3'), GlassTier.blur);
    });

    test('unknown devices get the default tier', () {
      expect(GlassTierPolicy.initialTierFor(''), GlassTier.standard);
      expect(GlassTierPolicy.initialTierFor('iPad14,1'), GlassTier.standard);
    });
  });

  group('GlassController', () {
    test('steps down but never up, and stops at blur', () {
      final c = GlassController(deviceTier: GlassTier.premium);
      addTearDown(c.dispose);
      var notified = 0;
      c
        ..addListener(() => notified++)
        ..stepDown();
      expect(c.tier, GlassTier.standard);
      c.stepDown();
      expect(c.tier, GlassTier.blur);
      c.stepDown();
      expect(c.tier, GlassTier.blur);
      expect(notified, 2);
    });

    test('Reduce Transparency and Low Power Mode force solid while on', () {
      final c = GlassController(deviceTier: GlassTier.standard);
      addTearDown(c.dispose);
      c.updateFlags(const AccessibilityFlags(reduceTransparency: true));
      expect(c.tier, GlassTier.solid);
      c.updateFlags(AccessibilityFlags.unknown);
      expect(c.tier, GlassTier.standard);
      c.updateFlags(const AccessibilityFlags(lowPowerMode: true));
      expect(c.tier, GlassTier.solid);
    });

    test('a failed probe drops to solid', () {
      final c = GlassController(deviceTier: GlassTier.premium)
        ..markProbeFailed();
      addTearDown(c.dispose);
      expect(c.tier, GlassTier.solid);
    });

    test('frame budget steps down after consecutive slow frames', () {
      final c = GlassController(deviceTier: GlassTier.premium);
      addTearDown(c.dispose);
      final budget = GlassFrameBudget(c, framesOverBudget: 3);
      expect(budget.budget, XpMotion.frameBudget);
    });
  });

  group('AccessibilityFlagsChannel', () {
    const methods = MethodChannel(AccessibilityFlagsChannel.methodChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(methods, null));

    test('reads the snapshot from iOS', () async {
      messenger.setMockMethodCallHandler(methods, (call) async {
        expect(call.method, 'snapshot');
        return {
          'reduceTransparency': true,
          'lowPowerMode': false,
          'deviceModel': 'iPhone18,1',
        };
      });
      final flags = await const AccessibilityFlagsChannel().read();
      expect(flags.reduceTransparency, isTrue);
      expect(flags.lowPowerMode, isFalse);
      expect(flags.deviceModel, 'iPhone18,1');
    });

    test(
      'falls back to unknown flags without a platform implementation',
      () async {
        final flags = await const AccessibilityFlagsChannel().read();
        expect(flags, AccessibilityFlags.unknown);
      },
    );

    test('start() turns Reduce Transparency into the solid tier and follows '
        'changes', () async {
      messenger.setMockMethodCallHandler(
        methods,
        (call) async => {
          'reduceTransparency': false,
          'deviceModel': 'iPhone16,2',
        },
      );
      final events = StreamController<AccessibilityFlags>();
      final controller = await GlassController.start(
        channel: _FakeChannel(events.stream),
      );
      addTearDown(controller.dispose);
      expect(controller.tier, GlassTier.premium);
      events.add(const AccessibilityFlags(reduceTransparency: true));
      await Future<void>.delayed(Duration.zero);
      expect(controller.tier, GlassTier.solid);
      await events.close();
    });
  });

  group('GlassSurface', () {
    testWidgets('tier 0 draws no backdrop filter; tier 1 does', (tester) async {
      Future<int> filters(GlassTier tier) async {
        await tester.pumpWidget(
          signalHarness(
            tier: tier,
            child: const SizedBox(
              height: 62,
              child: GlassSurface(
                variant: GlassVariant.control,
                child: SizedBox.expand(),
              ),
            ),
          ),
        );
        return find.byType(BackdropFilter).evaluate().length;
      }

      expect(await filters(GlassTier.solid), 0);
      expect(await filters(GlassTier.blur), greaterThan(0));
    });

    testWidgets('Reduce Transparency from the channel makes glass solid', (
      tester,
    ) async {
      await tester.pumpWidget(
        signalHarness(
          tier: GlassTier.premium,
          flags: const AccessibilityFlags(reduceTransparency: true),
          child: const SizedBox(
            height: 62,
            child: GlassSurface(
              variant: GlassVariant.control,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('overMedia is capped at the blur tier', (tester) async {
      await tester.pumpWidget(
        signalHarness(
          tier: GlassTier.premium,
          child: const SizedBox(
            height: 44,
            child: GlassSurface(
              variant: GlassVariant.overMedia,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsWidgets);
    });

    testWidgets('content colour follows the recipe', (tester) async {
      late Color onMedia;
      late Color onControl;
      await tester.pumpWidget(
        signalHarness(
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: GlassSurface(
                  variant: GlassVariant.overMedia,
                  child: Builder(
                    builder: (c) {
                      onMedia = GlassSurface.contentColorOf(c);
                      return const SizedBox();
                    },
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: GlassSurface(
                  variant: GlassVariant.control,
                  child: Builder(
                    builder: (c) {
                      onControl = GlassSurface.contentColorOf(c);
                      return const SizedBox();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      expect(onMedia, XpColors.light.onMedia);
      expect(onControl, XpColors.light.ink);
    });

    test('Increase Contrast raises tint to 90 % and borders to ink 40 %', () {
      for (final variant in GlassVariant.values) {
        final r = XpGlass.light
            .recipe(variant)
            .increasedContrast(XpColors.light.ink);
        expect(r.tint.a, greaterThanOrEqualTo(0.9 - 1e-3));
        expect(r.border.a, closeTo(0.4, 1e-3));
        expect(r.border.toARGB32() & 0xFFFFFF, 0x0B0B0C);
      }
    });

    test('six variants have a recipe in both themes', () {
      for (final glass in [XpGlass.light, XpGlass.dark]) {
        for (final variant in GlassVariant.values) {
          expect(glass.recipes[variant], isNotNull);
        }
      }
      expect(GlassVariant.values, hasLength(6));
      expect(GlassTier.values, hasLength(4));
    });
  });

  group('goldens, tiers 0 and 1', () {
    setUpAll(loadSignalFonts);

    for (final tier in [GlassTier.solid, GlassTier.blur]) {
      for (final brightness in Brightness.values) {
        for (final highContrast in [false, true]) {
          final name =
              'glass_tier${tier.index}_${brightness.name}'
              '${highContrast ? '_hc' : ''}';
          testWidgets(name, skip: !goldensSupported, (tester) async {
            await tester.pumpWidget(
              signalHarness(
                brightness: brightness,
                tier: tier,
                highContrast: highContrast,
                child: RepaintBoundary(
                  key: const ValueKey('golden'),
                  child: GalleryBackdrop(
                    child: Column(
                      children: [
                        for (final variant in GlassVariant.values)
                          Padding(
                            padding: const EdgeInsetsDirectional.symmetric(
                              vertical: 6,
                            ),
                            child: SizedBox(
                              height: 48,
                              child: GlassSurface(
                                variant: variant,
                                child: Center(
                                  child: Builder(
                                    builder: (c) => Text(
                                      variant.name,
                                      style: XpType.of(c).monoLabel.copyWith(
                                        color: GlassSurface.contentColorOf(c),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await expectLater(
              find.byKey(const ValueKey('golden')),
              matchesGoldenFile('goldens/$name.png'),
            );
          });
        }
      }
    }
  });
}

class _FakeChannel extends AccessibilityFlagsChannel {
  new(this._changes);

  final Stream<AccessibilityFlags> _changes;

  @override
  Stream<AccessibilityFlags> changes() => _changes;
}
