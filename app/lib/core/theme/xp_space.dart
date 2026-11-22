import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/xp_colors.dart';

/// Spacing, sizes and touch targets (DESIGN_SYSTEM 5), in logical points.
///
/// These do not change between themes, so they are constants rather than a
/// theme extension. Only [hairline] depends on context (pixel ratio and
/// Increase Contrast).
abstract final class XpSpace {
  /// 4 pt.
  static const double s4 = 4;

  /// 8 pt.
  static const double s8 = 8;

  /// 12 pt.
  static const double s12 = 12;

  /// 16 pt.
  static const double s16 = 16;

  /// 20 pt.
  static const double s20 = 20;

  /// 24 pt.
  static const double s24 = 24;

  /// 32 pt.
  static const double s32 = 32;

  /// 40 pt.
  static const double s40 = 40;

  /// Gap between a figure and its tiny caption, or icon and text in a pill.
  static const double s2 = 2;

  /// Gap between icon and label inside a pill.
  static const double s6 = 6;

  /// Screen margin for content.
  static const double screenMargin = 24;

  /// Screen margin for floating controls.
  static const double floatingMargin = 16;

  /// Screen margin for bottom sheets.
  static const double sheetMargin = 8;

  /// Ledger row height.
  static const double ledgerRow = 36;

  /// Receipt group row height.
  static const double receiptGroupRow = 44;

  /// List row height.
  static const double listRow = 54;

  /// Minimum touch target edge (44 × 44).
  static const double minTarget = 44;

  /// Tab bar height.
  static const double tabBarHeight = 62;

  /// Height of the well behind each tab item.
  static const double tabItemWell = 50;

  /// Horizontal inset of the tab items inside the bar.
  static const double tabBarInset = 6;

  /// Ask button diameter.
  static const double askButton = 62;

  /// Capture dock inner padding.
  static const double dockPadding = 14;

  /// Capture dock side buttons.
  static const double dockSideButton = 48;

  /// Capture dock record button.
  static const double dockRecordButton = 56;

  /// Halo ring width around the record button.
  static const double recordHalo = 6;

  /// Top glass button diameter.
  static const double topButton = 44;

  /// Glass pill (mode chip) height.
  static const double pillHeight = 32;

  /// Glass pill horizontal padding.
  static const double pillPadding = 12;

  /// Primary button height.
  static const double buttonHeight = 52;

  /// Chip visual height (hit area is [minTarget]).
  static const double chipHeight = 38;

  /// Chip horizontal padding.
  static const double chipPadding = 14;

  /// Slip padding.
  static const double slipPadding = 18;

  /// Sheet grabber width.
  static const double grabberWidth = 38;

  /// Sheet grabber height.
  static const double grabberHeight = 5;

  /// Gap between chart bars.
  static const double chartBarGap = 5;

  /// Mini bar chart height.
  static const double miniBarsHeight = 64;

  /// Ledger dot.
  static const double dotLedger = 7;

  /// Unread dot.
  static const double dotUnread = 6;

  /// Nudge dot.
  static const double dotNudge = 18;

  /// Avatar diameter.
  static const double avatar = 34;

  /// Overlap between paired avatars.
  static const double avatarOverlap = 10;

  /// Avatar ring width (canvas-coloured).
  static const double avatarRing = 2;

  /// Thin progress bar height.
  static const double thinBar = 2;

  /// Goal bar height.
  static const double goalBar = 4;

  /// Switch track.
  static const Size switchTrack = Size(52, 32);

  /// Switch knob diameter.
  static const double switchKnob = 26;

  /// Step bar segment height.
  static const double stepBar = 3;

  /// Scan frame bracket arm length.
  static const double scanBracket = 26;

  /// Scan frame bracket stroke.
  static const double scanStroke = 2.5;

  /// Waveform bar width in the dock.
  static const double waveBar = 3;

  /// Waveform bar width in a transcript quote.
  static const double waveBarMini = 2;

  /// Dock waveform height.
  static const double waveHeight = 40;

  /// Transcript mini waveform height.
  static const double waveHeightMini = 14;

  /// Icon size in round glass buttons.
  static const double iconTop = 20;

  /// Icon size in the tab bar.
  static const double iconTab = 21;

  /// Icon size in the Ask button.
  static const double iconAsk = 24;

  /// Small icon inside pills.
  static const double iconPill = 12;

  /// Icon in a list row or disclosure.
  static const double iconRow = 17;

  /// Maximum width of a quoted utterance in the Ask thread.
  static const double quoteMaxWidth = 270;

  /// Legibility scrim height under camera controls.
  static const double cameraScrim = 120;

  /// Spinner diameter.
  static const double spinner = 20;

  /// Skeleton line height.
  static const double skeletonLine = 12;

  /// Progress ring diameter.
  static const double progressRing = 44;

  /// Progress ring stroke.
  static const double progressRingStroke = 3;

  /// Count badge minimum diameter.
  static const double countBadge = 18;

  /// Distance of floating bottom controls from the bottom edge:
  /// `max(safeAreaBottom, 8) + 8` (DESIGN_SYSTEM 5).
  static double bottomControlOffset(BuildContext context) =>
      math.max(MediaQuery.paddingOf(context).bottom, s8) + s8;

  /// Bottom padding for scrollable content under the tab bar, so the last
  /// row clears the glass.
  static double contentBottomPadding(BuildContext context) =>
      tabBarHeight + bottomControlOffset(context) + s16;

  /// Width, in text-scaled points, below which side-by-side layouts (a
  /// title beside a figure, two buttons in a row) stack instead.
  static const double stackBelowWidth = 300;

  /// Whether [width] is too narrow for side-by-side content at the current
  /// text size.
  static bool isNarrow(BuildContext context, double width) =>
      width / MediaQuery.textScalerOf(context).scale(1) < stackBelowWidth;

  /// One hairline in logical points: one physical pixel, two under
  /// Increase Contrast.
  static double hairline(BuildContext context) =>
      XpColors.of(context).hairlineWeight /
      MediaQuery.devicePixelRatioOf(context);
}

/// Corner radii (DESIGN_SYSTEM 5).
abstract final class XpRadius {
  /// Slip corners.
  static const double slip = 6;

  /// Chart bar corners.
  static const double chartBar = 2;

  /// Bottom sheet corners.
  static const double sheet = 38;

  /// Capture dock corners.
  static const double dock = 34;

  /// Receipt paper corners.
  static const double paper = 3;

  /// Sheet grabber and thin bars.
  static const double hairPill = 3;

  /// Search field and text wells are stadiums; this is their fallback.
  static const double well = 24;

  /// Slip corners as a [BorderRadiusDirectional].
  static const BorderRadiusDirectional slipAll = BorderRadiusDirectional.all(
    Radius.circular(slip),
  );

  /// Chart bar corners as a [BorderRadiusDirectional].
  static const BorderRadiusDirectional chartBarAll =
      BorderRadiusDirectional.all(Radius.circular(chartBar));

  /// Thin pill corners as a [BorderRadiusDirectional].
  static const BorderRadiusDirectional hairPillAll =
      BorderRadiusDirectional.all(Radius.circular(hairPill));

  /// Sheet corners as a [BorderRadiusDirectional].
  static const BorderRadiusDirectional sheetAll = BorderRadiusDirectional.all(
    Radius.circular(sheet),
  );

  /// Dock corners as a [BorderRadiusDirectional].
  static const BorderRadiusDirectional dockAll = BorderRadiusDirectional.all(
    Radius.circular(dock),
  );

  /// Receipt paper corners as a [BorderRadiusDirectional].
  static const BorderRadiusDirectional paperAll = BorderRadiusDirectional.all(
    Radius.circular(paper),
  );
}
