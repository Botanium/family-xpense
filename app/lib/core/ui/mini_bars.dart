import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';

/// The one thin chart: daily bars, 64 pt high, today's bar in orange
/// (DESIGN_SYSTEM 8.2). Screen readers hear [summary], never the bars.
class MiniBars extends StatelessWidget {
  /// Creates a mini bar chart.
  const new({
    required this.values,
    required this.summary,
    this.highlightLast = true,
    super.key,
  });

  /// One non-negative value per day, oldest first.
  final List<int> values;

  /// Spoken summary, such as "Daily spending for November 1 to 21; today is
  /// the highest". Required: a chart without one is not accessible.
  final String summary;

  /// Whether the last bar is today's (orange: a "live" mark).
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return Semantics(
      label: summary,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: XpSpace.miniBarsHeight,
          width: double.infinity,
          child: CustomPaint(
            painter: _BarsPainter(
              values: values,
              bar: colors.ink.withValues(alpha: XpOpacity.chartBar),
              live: highlightLast ? colors.accent : null,
              rtl: Directionality.of(context) == TextDirection.rtl,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  const new({
    required this.values,
    required this.bar,
    required this.live,
    required this.rtl,
  });

  final List<int> values;
  final Color bar;
  final Color? live;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxValue = math.max(1, values.reduce(math.max));
    const gap = XpSpace.chartBarGap;
    final width = (size.width - gap * (values.length - 1)) / values.length;
    if (width <= 0) return;
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < values.length; i++) {
      final h = math.max(XpSpace.thinBar, size.height * values[i] / maxValue);
      final slot = rtl ? values.length - 1 - i : i;
      final left = slot * (width + gap);
      paint.color = live != null && i == values.length - 1 ? live! : bar;
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          size.height - h,
          left + width,
          size.height,
          const Radius.circular(XpRadius.chartBar),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.bar != bar ||
      old.live != live ||
      old.rtl != rtl ||
      !_same(old.values, values);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
