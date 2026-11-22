import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// Text tabs with an ink underline, horizontally scrollable
/// (DESIGN_SYSTEM 8.1, segmented control).
class XpFilterBar extends StatelessWidget {
  /// Creates a filter bar.
  const new({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  /// Filter names, in order.
  final List<String> labels;

  /// Index of the active filter.
  final int selectedIndex;

  /// Called with the tapped index.
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: XpSpace.s20),
              child: XpPressable(
                onPressed: () {
                  unawaited(XpHaptics.picked());
                  onSelected(i);
                },
                selected: i == selectedIndex,
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: type.subhead.copyWith(
                          color: i == selectedIndex
                              ? colors.ink
                              : colors.inkSecondary,
                          fontWeight: i == selectedIndex
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: XpSpace.s6),
                      SizedBox(
                        height: XpSpace.thinBar,
                        child: i == selectedIndex
                            ? ColoredBox(color: colors.ink)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Toggle: ink track when on, 44 pt hit area (DESIGN_SYSTEM 8.1).
class XpSwitch extends StatelessWidget {
  /// Creates a switch.
  const new({
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    super.key,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value.
  final ValueChanged<bool>? onChanged;

  /// Spoken label, such as "Split by category".
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final motion = XpMotion.of(context);
    final elevation = XpElevation.of(context);
    const track = XpSpace.switchTrack;
    final inset = (track.height - XpSpace.switchKnob) / 2;
    return XpPressable(
      onPressed: onChanged == null
          ? null
          : () {
              unawaited(XpHaptics.picked());
              onChanged!(!value);
            },
      semanticLabel: semanticLabel,
      toggled: value,
      excludeChildSemantics: true,
      child: AnimatedContainer(
        duration: motion.fast,
        curve: XpMotion.fastCurve,
        width: track.width,
        height: track.height,
        padding: EdgeInsetsDirectional.all(inset),
        decoration: ShapeDecoration(
          color: value ? colors.selectedFill : colors.perforation,
          shape: const StadiumBorder(),
        ),
        child: AnimatedAlign(
          duration: motion.fast,
          curve: XpMotion.fastCurve,
          alignment: value
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: SizedBox.square(
            dimension: XpSpace.switchKnob,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: value ? colors.onSelectedFill : colors.switchKnobOff,
                shape: BoxShape.circle,
                boxShadow: elevation.knob,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
