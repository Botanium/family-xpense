import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/primitives.dart';

/// The two content shadows (DESIGN_SYSTEM 2). Glass shadows live in the
/// glass recipes instead.
@immutable
class XpElevation extends ThemeExtension<XpElevation> {
  /// Creates the shadow set.
  const new({required this.slip, required this.knob});

  /// Light theme shadows, from the Ask artboard.
  static const XpElevation light = XpElevation(
    slip: [
      BoxShadow(
        color: Color.fromRGBO(11, 11, 12, 0.05),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        color: Color.fromRGBO(11, 11, 12, 0.07),
        offset: Offset(0, 16),
        blurRadius: 34,
      ),
    ],
    knob: [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.18),
        offset: Offset(0, 2),
        blurRadius: 6,
      ),
    ],
  );

  /// Dark theme shadows: ink shadows vanish on graphite, so black is used at
  /// higher strength.
  static const XpElevation dark = XpElevation(
    slip: [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.40),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.35),
        offset: Offset(0, 16),
        blurRadius: 34,
      ),
    ],
    knob: [
      BoxShadow(
        color: Color.fromRGBO(0, 0, 0, 0.40),
        offset: Offset(0, 2),
        blurRadius: 6,
      ),
    ],
  );

  /// Shadow under the receipt paper preview on the camera screen.
  static const List<BoxShadow> paper = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.55),
      offset: Offset(0, 24),
      blurRadius: 50,
    ),
  ];

  /// Returns the shadows of the nearest theme.
  static XpElevation of(BuildContext context) {
    final elevation = Theme.of(context).extension<XpElevation>();
    assert(elevation != null, 'XpElevation missing: use buildAppTheme.');
    return elevation ?? light;
  }

  /// Under a slip, the one raised content surface.
  final List<BoxShadow> slip;

  /// Under the switch knob.
  final List<BoxShadow> knob;

  /// Black used for the camera legibility scrim.
  static const Color scrim = XpPalette.black0;

  /// Tokens are fixed per theme, so a copy is the same value.
  @override
  XpElevation copyWith() => this;

  /// Theme changes cut rather than animate, so this snaps.
  @override
  XpElevation lerp(covariant XpElevation? other, double t) =>
      other == null || t < 0.5 ? this : other;
}
