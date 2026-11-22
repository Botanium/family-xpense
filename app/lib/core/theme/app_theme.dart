import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/xp_colors.dart';
import 'package:xpense_app/core/theme/xp_elevation.dart';
import 'package:xpense_app/core/theme/xp_glass.dart';
import 'package:xpense_app/core/theme/xp_type.dart';

/// Theme changes cut instead of cross-fading (DESIGN_SYSTEM 2). Pass to
/// `MaterialApp.themeAnimationStyle`.
const AnimationStyle xpThemeAnimationStyle = AnimationStyle.noAnimation;

/// The four Signal themes, each built once.
///
/// Wire into `MaterialApp` as `theme`, `darkTheme`, `highContrastTheme` and
/// `highContrastDarkTheme`; Flutter picks the high-contrast pair when iOS
/// Increase Contrast is on.
abstract final class XpThemes {
  /// Light.
  static final ThemeData light = buildAppTheme(Brightness.light);

  /// Graphite dark.
  static final ThemeData dark = buildAppTheme(Brightness.dark);

  /// Light with Increase Contrast.
  static final ThemeData lightHighContrast = buildAppTheme(
    Brightness.light,
    highContrast: true,
  );

  /// Dark with Increase Contrast.
  static final ThemeData darkHighContrast = buildAppTheme(
    Brightness.dark,
    highContrast: true,
  );
}

/// Returns the colour slots for [brightness] and contrast.
XpColors xpColorsFor(Brightness brightness, {bool highContrast = false}) =>
    switch ((brightness, highContrast)) {
      (Brightness.light, false) => XpColors.light,
      (Brightness.light, true) => XpColors.lightHighContrast,
      (Brightness.dark, false) => XpColors.dark,
      (Brightness.dark, true) => XpColors.darkHighContrast,
    };

/// Builds the Signal [ThemeData] for [brightness].
///
/// The [ColorScheme] is written by hand from the semantic slots (never
/// `fromSeed`), and every Signal extension is attached so components can
/// read tokens with `XpColors.of(context)` and friends.
ThemeData buildAppTheme(Brightness brightness, {bool highContrast = false}) {
  final c = xpColorsFor(brightness, highContrast: highContrast);
  final type = XpType.from(c);
  final glass = brightness == Brightness.light ? XpGlass.light : XpGlass.dark;
  final elevation = brightness == Brightness.light
      ? XpElevation.light
      : XpElevation.dark;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primaryFill,
    onPrimary: c.onPrimaryFill,
    primaryContainer: c.surfaceSunken,
    onPrimaryContainer: c.ink,
    secondary: c.ink,
    onSecondary: c.surface,
    secondaryContainer: c.surfaceSunken,
    onSecondaryContainer: c.ink,
    // Orange is the "act or live" mark, never a second button colour; it is
    // parked in tertiary so no Material default picks it up as primary.
    tertiary: c.accent,
    onTertiary: c.inkOnAccent,
    error: c.danger,
    onError: c.surface,
    surface: c.surface,
    onSurface: c.ink,
    onSurfaceVariant: c.inkSecondary,
    surfaceDim: c.canvas,
    surfaceBright: c.surface,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.canvas,
    surfaceContainerHigh: c.surfaceSunken,
    surfaceContainerHighest: c.surfaceSunken,
    outline: c.perforation,
    outlineVariant: c.hairline,
    shadow: c.ink,
    scrim: c.ink,
    inverseSurface: c.ink,
    onInverseSurface: c.canvas,
    inversePrimary: c.surface,
    surfaceTint: const Color(0x00000000),
  );

  final textTheme = TextTheme(
    displayLarge: type.figureHero,
    displayMedium: type.figureLarge,
    displaySmall: type.figureMedium,
    headlineSmall: type.quote,
    titleLarge: type.title,
    titleMedium: type.bodyStrong,
    titleSmall: type.subhead,
    bodyLarge: type.body,
    bodyMedium: type.body,
    bodySmall: type.caption,
    labelLarge: type.button,
    labelMedium: type.chip,
    labelSmall: type.meta,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    dividerColor: c.hairline,
    fontFamily: XpFonts.sans,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.surfaceSunken,
    splashColor: const Color(0x00000000),
    hoverColor: const Color(0x00000000),
    focusColor: c.surfaceSunken,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.ink,
      selectionColor: c.ink.withValues(alpha: 0.18),
      selectionHandleColor: c.ink,
    ),
    cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
      brightness: brightness,
      primaryColor: c.ink,
      scaffoldBackgroundColor: c.canvas,
      barBackgroundColor: c.surface,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      },
    ),
    extensions: [c, type, glass, elevation],
  );
}
