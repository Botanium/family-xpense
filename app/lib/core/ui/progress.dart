import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';

/// A 2 pt progress line on a hairline track (DESIGN_SYSTEM 8.1).
class ThinBar extends StatelessWidget {
  /// Creates a thin bar at [value] from 0 to 1.
  const new({
    required this.value,
    this.color,
    this.height = XpSpace.thinBar,
    this.semanticLabel,
    super.key,
  });

  /// Progress from 0 to 1; values above 1 draw full (over budget).
  final double value;

  /// Fill colour; defaults to ink.
  final Color? color;

  /// Bar height.
  final double height;

  /// Spoken label; the percentage is read as the value.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final clamped = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(value * 100).round()}%',
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.hairline,
            shape: const StadiumBorder(),
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: clamped,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: color ?? colors.ink,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The system activity indicator in secondary ink.
class XpSpinner extends StatelessWidget {
  /// Creates a spinner.
  const new({this.semanticLabel, super.key});

  /// Spoken label, such as "Loading".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    child: CupertinoActivityIndicator(
      color: XpColors.of(context).inkSecondary,
      animating: !XpMotion.of(context).isReduced,
    ),
  );
}

/// Placeholder rows while a list loads: still bars in the sunken colour.
/// Static on purpose, so Reduce Motion needs no special case.
class Skeleton extends StatelessWidget {
  /// Creates [rows] skeleton list rows.
  const new({this.rows = 3, this.semanticLabel, super.key});

  /// How many rows.
  final int rows;

  /// Spoken label, such as "Loading entries".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    Widget bar(double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        height: XpSpace.skeletonLine,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: colors.surfaceSunken,
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows; i++)
              SizedBox(
                height: XpSpace.listRow,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          bar(0.55 - (i % 3) * 0.08),
                          const SizedBox(height: XpSpace.s6),
                          bar(0.3),
                        ],
                      ),
                    ),
                    const SizedBox(width: XpSpace.s24),
                    SizedBox(width: XpSpace.s40 + XpSpace.s24, child: bar(1)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Onboarding progress in [count] segments (DESIGN_SYSTEM 8.1, page
/// control).
class StepBar extends StatelessWidget {
  /// Creates a step bar at [current] (1-based) of [count].
  const new({
    required this.current,
    required this.semanticLabel,
    this.count = 4,
    super.key,
  });

  /// Current step, 1-based.
  final int current;

  /// Number of steps.
  final int count;

  /// Spoken label, such as "Step 1 of 4".
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return Semantics(
      label: semanticLabel,
      child: Row(
        children: [
          for (var i = 1; i <= count; i++) ...[
            if (i > 1) const SizedBox(width: XpSpace.s4),
            Expanded(
              child: SizedBox(
                height: XpSpace.stepBar,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: i <= current ? colors.ink : colors.hairline,
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A thin ring with the percentage in mono at its centre (DESIGN_SYSTEM
/// 8.2).
class ProgressRing extends StatelessWidget {
  /// Creates a ring at [value] from 0 to 1.
  const new({required this.value, this.semanticLabel, super.key});

  /// Progress from 0 to 1.
  final double value;

  /// Spoken label, such as "Holiday fund".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final percent = '${(value * 100).round()}%';
    return Semantics(
      label: semanticLabel,
      value: percent,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: XpSpace.progressRing,
        child: CustomPaint(
          painter: _RingPainter(
            value: value.clamp(0.0, 1.0),
            track: colors.hairline,
            fill: colors.ink,
          ),
          child: Center(
            child: Text(
              percent,
              style: type.monoLabel.copyWith(letterSpacing: 0),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const new({required this.value, required this.track, required this.fill});

  final double value;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = XpSpace.progressRingStroke;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawArc(rect, 0, math.pi * 2, false, paint..color = track)
      ..drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * value,
        false,
        paint..color = fill,
      );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// A goal row: name, thin bar, percentage and pace in mono
/// (DESIGN_SYSTEM 8.2).
class GoalBar extends StatelessWidget {
  /// Creates a goal bar.
  const new({
    required this.label,
    required this.value,
    this.pace,
    this.color,
    super.key,
  });

  /// Goal name.
  final String label;

  /// Progress from 0 to 1.
  final double value;

  /// Pace line such as "ON TRACK · 120/MO"; upper-cased here.
  final String? pace;

  /// Bar colour; defaults to the `saved` colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final percent = '${(value * 100).round()}%';
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: type.bodyStrong)),
              Text(percent, style: type.figureBody),
            ],
          ),
          const SizedBox(height: XpSpace.s6),
          ThinBar(
            value: value,
            height: XpSpace.goalBar,
            color: color ?? colors.saved,
          ),
          if (pace != null) ...[
            const SizedBox(height: XpSpace.s6),
            Text(
              pace!.toUpperCase(),
              style: type.monoLabel.copyWith(color: colors.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
