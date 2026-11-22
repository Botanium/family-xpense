import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Loads the bundled Geist families so goldens show real glyphs instead of
/// the test font's boxes.
Future<void> loadSignalFonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(Uint8List.fromList(await File(path).readAsBytes()));
  final sans = FontLoader(XpFonts.sans);
  for (final w in ['Regular', 'Medium', 'SemiBold']) {
    sans.addFont(bytes('assets/fonts/geist/Geist-$w.ttf'));
  }
  final mono = FontLoader(XpFonts.mono);
  for (final w in ['Light', 'Regular', 'Medium']) {
    mono.addFont(bytes('assets/fonts/geist_mono/GeistMono-$w.ttf'));
  }
  await Future.wait([sans.load(), mono.load()]);
}

/// Wraps [child] in a Signal theme with the given brightness, text scale,
/// glass tier and accessibility flags.
Widget signalHarness({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  GlassTier tier = GlassTier.blur,
  bool highContrast = false,
  bool disableAnimations = true,
  AccessibilityFlags flags = AccessibilityFlags.unknown,
  double width = 390,
}) {
  final controller = GlassController(deviceTier: tier, flags: flags);
  final theme = buildAppTheme(brightness, highContrast: highContrast);
  return GlassScope(
    controller: controller,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeAnimationStyle: xpThemeAnimationStyle,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            highContrast: highContrast,
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            backgroundColor: theme.extension<XpColors>()!.canvas,
            body: SingleChildScrollView(
              child: Align(
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(width: width, child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Whether goldens can be compared here. Glyph rasterisation differs
/// between macOS and the Linux CI runner, so goldens are recorded and
/// verified on macOS only; CI skips them and says so.
final bool goldensSupported = Platform.isMacOS;

/// Skip reason for golden tests off macOS.
const String goldenSkipReason =
    'Goldens are recorded on macOS; the Linux CI runner rasterises glyphs '
    'differently. Run `flutter test test/ui` on a Mac to verify.';
