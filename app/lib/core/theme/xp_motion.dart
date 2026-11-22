import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Motion tokens (DESIGN_SYSTEM 7), already resolved for Reduce Motion.
///
/// Read with [XpMotion.of]: under Reduce Motion every duration is zero, so
/// state changes cut. Motion is never the only signal of a change.
enum XpMotion {
  /// Normal motion.
  standard(
    fast: Duration(milliseconds: 120),
    base: Duration(milliseconds: 220),
    slow: Duration(milliseconds: 360),
    count: Duration(milliseconds: 400),
  ),

  /// Reduce Motion: every duration is zero.
  reduced(
    fast: Duration.zero,
    base: Duration.zero,
    slow: Duration.zero,
    count: Duration.zero,
  );

  new({
    required this.fast,
    required this.base,
    required this.slow,
    required this.count,
  });

  /// Returns [reduced] when the platform asks for less motion, else
  /// [standard].
  static XpMotion of(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? reduced : standard;

  /// 120 ms: chip select, badge appear. Pair with [fastCurve].
  final Duration fast;

  /// 220 ms: card appear, field change. Pair with [baseCurve].
  final Duration base;

  /// 360 ms: sheet present, dock mode switch. Pair with [slowCurve].
  final Duration slow;

  /// 400 ms: figure roll when a balance changes.
  final Duration count;

  /// How long the undo toast stays (DESIGN_SYSTEM 8.2). Not motion, so it
  /// does not drop to zero under Reduce Motion.
  static const Duration toastLifetime = Duration(seconds: 10);

  /// Raster time per frame above which glass counts a frame as slow (one
  /// 60 Hz frame). WP-S2 tunes it per device.
  static const Duration frameBudget = Duration(microseconds: 16667);

  /// Whether motion is off (every duration is zero).
  bool get isReduced => base == Duration.zero;

  /// Ease-out, for [fast].
  static const Curve fastCurve = Curves.easeOut;

  /// Ease-out-cubic, for [base].
  static const Curve baseCurve = Curves.easeOutCubic;

  /// Spring with damping ratio 0.86, for [slow].
  static const Curve slowCurve = XpSpringCurve();

  /// Ease-out-cubic, for [count].
  static const Curve countCurve = Curves.easeOutCubic;

  /// Spring used by sheets and the dock, damping ratio 0.86.
  static final SpringDescription spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 300,
    ratio: 0.86,
  );
}

/// A critically-damped-ish spring (ratio 0.86) expressed as a [Curve], so
/// implicit animations can use the `slow` token.
class XpSpringCurve extends Curve {
  /// Creates the spring curve.
  const new();

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(XpMotion.spring, 0, 1, 0);
    // The spring settles in about 0.45 s at this stiffness; map t onto that.
    return sim.x(t * 0.45);
  }
}

/// Haptics per event (DESIGN_SYSTEM 7). Scrolling, tab changes and typing
/// have none.
abstract final class XpHaptics {
  /// Mic start and mic stop.
  static Future<void> micToggle() => HapticFeedback.lightImpact();

  /// A chip or option picked.
  static Future<void> picked() => HapticFeedback.selectionClick();

  /// Saved.
  static Future<void> saved() => HapticFeedback.successNotification();

  /// Duplicate warning, limit reached.
  static Future<void> warning() => HapticFeedback.warningNotification();

  /// Destructive confirm.
  static Future<void> destructive() => HapticFeedback.mediumImpact();
}
