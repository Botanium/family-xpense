/// Tier 1 design tokens: raw values named by what they measure.
///
/// Nothing outside `lib/core/theme/` reads these. Components read the
/// semantic slots in `xp_colors.dart`, `xp_type.dart`, `xp_space.dart`,
/// `xp_glass.dart`, `xp_motion.dart` and `xp_elevation.dart` instead
/// (DESIGN_SYSTEM 2). Colour names carry the approximate HSL lightness, so
/// `stone92` is a warm grey at about 92 % lightness and `ink04` is a near
/// black at about 4 %.
library;

import 'dart:ui';

/// Raw colours of the Signal palette (DESIGN_SYSTEM 3.1).
abstract final class XpPalette {
  // Stone (light theme neutrals).

  /// `#ECEBE7`, light canvas.
  static const Color stone92 = Color(0xFFECEBE7);

  /// `#FAF9F6`, light surface and glass tint.
  static const Color stone97 = Color(0xFFFAF9F6);

  /// `#E6E4DF`, light sunken well. DESIGN_SYSTEM proposed `#E3E1DC`, which
  /// gives secondary ink (search placeholders) only 4.41:1; WP-03 lifted it
  /// one step to reach 4.5:1.
  static const Color stone89 = Color(0xFFE6E4DF);

  /// `#D8D6D0`, light hairline.
  static const Color stone83 = Color(0xFFD8D6D0);

  /// `#DEDCD6`, light soft hairline.
  static const Color stone86 = Color(0xFFDEDCD6);

  /// `#A9A7A0`, light dotted leader.
  static const Color stone64 = Color(0xFFA9A7A0);

  /// `#BDBAB2`, light perforation.
  static const Color stone72 = Color(0xFFBDBAB2);

  /// `#67665F`, light secondary ink.
  static const Color stone39 = Color(0xFF67665F);

  /// `#4A4944`, light secondary ink under Increase Contrast.
  static const Color stone28 = Color(0xFF4A4944);

  /// `#7A7871`, light tertiary ink (large-figure decimals).
  static const Color stone46 = Color(0xFF7A7871);

  /// `#3F3E3A`, light inactive tab.
  static const Color stone24 = Color(0xFF3F3E3A);

  /// `#F4F2EC`, receipt paper in both themes.
  static const Color paper94 = Color(0xFFF4F2EC);

  /// `#0B0B0C`, ink.
  static const Color ink04 = Color(0xFF0B0B0C);

  /// Pure white, used only at low alpha for glass rims.
  static const Color white100 = Color(0xFFFFFFFF);

  /// Pure black, used for the dark camera backdrop and shadows.
  static const Color black0 = Color(0xFF000000);

  // Graphite (dark theme neutrals).

  /// `#161617`, dark canvas.
  static const Color graphite09 = Color(0xFF161617);

  /// `#1F1F21`, dark surface.
  static const Color graphite12 = Color(0xFF1F1F21);

  /// `#101011`, dark sunken well.
  static const Color graphite06 = Color(0xFF101011);

  /// `#1C1C1E`, camera backdrop (light) and dark sheet tint.
  static const Color graphite11 = Color(0xFF1C1C1E);

  /// `#222224`, dark control glass tint.
  static const Color graphite14 = Color(0xFF222224);

  /// `#2C2C2F`, dark hairline.
  static const Color graphite18 = Color(0xFF2C2C2F);

  /// `#252527`, dark soft hairline.
  static const Color graphite15 = Color(0xFF252527);

  /// `#4A4A4E`, dark dotted leader.
  static const Color graphite30 = Color(0xFF4A4A4E);

  /// `#3A3A3D`, dark perforation.
  static const Color graphite23 = Color(0xFF3A3A3D);

  /// `#F2F1ED`, dark ink.
  static const Color stone94 = Color(0xFFF2F1ED);

  /// `#A3A199`, dark secondary ink.
  static const Color stone62 = Color(0xFFA3A199);

  /// `#C9C7BF`, dark secondary ink under Increase Contrast.
  static const Color stone77 = Color(0xFFC9C7BF);

  /// `#77756E`, dark tertiary ink.
  static const Color stone45 = Color(0xFF77756E);

  /// `#B4B2AA`, dark inactive tab.
  static const Color stone69 = Color(0xFFB4B2AA);

  // Signal and meaning colours.

  /// `#FF5B1A`, the one signal orange.
  static const Color orange55 = Color(0xFFFF5B1A);

  /// `#127047`, light income.
  static const Color green26 = Color(0xFF127047);

  /// `#4CC38A`, dark income.
  static const Color green53 = Color(0xFF4CC38A);

  /// `#2B59FF`, light saved.
  static const Color blue58 = Color(0xFF2B59FF);

  /// `#7C9BFF`, dark saved.
  static const Color blue74 = Color(0xFF7C9BFF);

  /// `#A15C00`, light loan.
  static const Color amber32 = Color(0xFFA15C00);

  /// `#E0A04A`, dark loan.
  static const Color amber58 = Color(0xFFE0A04A);

  /// `#B3261E`, light danger.
  static const Color red41 = Color(0xFFB3261E);

  /// `#FF8A80`, dark danger.
  static const Color red75 = Color(0xFFFF8A80);

  // Category keys cat1 … cat8 (DESIGN_SYSTEM 3.1). Light values are the
  // planning candidates; dark values are lightened counterparts chosen in
  // WP-03 and checked at 3:1 or better in test/theme/contrast_test.dart.

  /// Light category colours, `cat1` to `cat8`.
  static const List<Color> categoriesLight = [
    Color(0xFF127047),
    Color(0xFF2B59FF),
    Color(0xFFA15C00),
    Color(0xFF8A3FFC),
    Color(0xFFC2255C),
    Color(0xFF0E7490),
    Color(0xFF5F6B00),
    Color(0xFF6B5B4B),
  ];

  /// Dark category colours, `cat1` to `cat8`.
  static const List<Color> categoriesDark = [
    Color(0xFF4CC38A),
    Color(0xFF7C9BFF),
    Color(0xFFE0A04A),
    Color(0xFFB392FF),
    Color(0xFFF27DA6),
    Color(0xFF4FB8D0),
    Color(0xFFA8B83A),
    Color(0xFFB8A593),
  ];
}

/// Raw opacities used to derive translucent slots.
abstract final class XpAlpha {
  /// Active tab well over light glass: ink at 7 %.
  static const double tabWellLight = 0.07;

  /// Active tab well over dark glass: white at 10 %.
  static const double tabWellDark = 0.10;

  /// Accent halo around the recording button, light.
  static const double haloLight = 0.16;

  /// Accent halo around the recording button, dark.
  static const double haloDark = 0.22;

  /// Neutral wells inside glass (dock side buttons): ink at 6 %.
  static const double controlWellLight = 0.06;

  /// Neutral wells inside dark glass: white at 8 %.
  static const double controlWellDark = 0.08;

  /// Sheet grabber: ink at 20 %.
  static const double grabber = 0.20;

  /// Lock overlay scrim over the blurred canvas.
  static const double lockScrim = 0.72;

  /// Camera legibility scrim at its darkest (DESIGN_SYSTEM 6.2).
  static const double cameraScrim = 0.35;
}
