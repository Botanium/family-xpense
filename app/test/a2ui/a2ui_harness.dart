/// Shared set-up for the a2ui tests: the Signal theme with the app's
/// localizations, and the surface fixtures shared with `xpense_shared`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/testing/fake_xpense_actions.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// The fixtures folder of `xpense_shared`, from the app package.
const String fixturesDir = '../packages/xpense_shared/test/fixtures/surfaces';

/// Every fixture name, sorted.
List<String> fixtureNames() =>
    Directory(fixturesDir)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .map((n) => n.substring(0, n.length - 5))
        .toList()
      ..sort();

/// The messages of fixture [name].
List<Map<String, Object?>> fixture(String name) => (jsonDecode(
  File('$fixturesDir/$name.json').readAsStringSync(),
) as List<Object?>).cast<Map<String, Object?>>();

/// The surface id a fixture creates.
String surfaceIdOf(List<Map<String, Object?>> messages) =>
    messages
            .map((m) => m['createSurface'])
            .whereType<Map<String, Object?>>()
            .single['surfaceId']!
        as String;

/// The key of the boundary goldens capture.
const ValueKey<String> goldenKey = ValueKey('golden');

/// A Signal-themed app around [child], with the app's localizations.
Widget a2uiHarness({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  double width = 390,
}) {
  final theme = buildAppTheme(brightness);
  return GlassScope(
    controller: GlassController(deviceTier: GlassTier.solid),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeAnimationStyle: xpThemeAnimationStyle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: true,
          ),
          child: Scaffold(
            backgroundColor: theme.extension<XpColors>()!.canvas,
            body: SingleChildScrollView(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(
                  width: width,
                  child: RepaintBoundary(
                    key: goldenKey,
                    child: ColoredBox(
                      color: theme.extension<XpColors>()!.canvas,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.all(16),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A host over [actions] (a fresh fake by default), with [messages] added.
({XpenseSurfaceHost host, FakeXpenseActions actions, List<AgentAction> sent})
hostWith(List<Map<String, Object?>> messages, {FakeXpenseActions? actions}) {
  final fake = actions ?? FakeXpenseActions();
  final sent = <AgentAction>[];
  final host = XpenseSurfaceHost(actions: fake, onAgentAction: sent.add)
    ..addMessages(messages);
  addTearDown(host.dispose);
  return (host: host, actions: fake, sent: sent);
}

/// Pumps the whole thread of [host] in the harness.
Future<void> pumpThread(
  WidgetTester tester,
  XpenseSurfaceHost host, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = const Size(390, 2400) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    a2uiHarness(
      brightness: brightness,
      textScale: textScale,
      child: SurfaceThread(host: host),
    ),
  );
  await tester.pump();
}
