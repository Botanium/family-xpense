import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// One option of [ChoiceChips].
@immutable
class ChoiceOption<T> {
  /// Creates an option.
  const new({required this.value, required this.label});

  /// Value reported when picked.
  final T value;

  /// Chip text.
  final String label;
}

/// Outline chips in a wrap; the selected chip is filled with ink
/// (DESIGN_SYSTEM 8.2). Each chip is 38 pt high inside a 44 pt hit area and
/// announces its selected state.
class ChoiceChips<T> extends StatelessWidget {
  /// Creates a chip group.
  const new({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// The options, in order.
  final List<ChoiceOption<T>> options;

  /// The selected value, or null.
  final T? selected;

  /// Called with the picked value.
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: XpSpace.s8,
    children: [
      for (final option in options)
        XpChip(
          label: option.label,
          selected: option.value == selected,
          onPressed: onSelected == null
              ? null
              : () {
                  unawaited(XpHaptics.picked());
                  onSelected!(option.value);
                },
        ),
    ],
  );
}

/// A single outline chip; filled with ink when [selected].
class XpChip extends StatelessWidget {
  /// Creates a chip.
  const new({
    required this.label,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  /// Chip text.
  final String label;

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Whether the chip is the selected one.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final motion = XpMotion.of(context);
    return XpPressable(
      onPressed: onPressed,
      selected: selected,
      child: AnimatedContainer(
        duration: motion.fast,
        curve: XpMotion.fastCurve,
        constraints: const BoxConstraints(minHeight: XpSpace.chipHeight),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: XpSpace.chipPadding,
          vertical: XpSpace.s8,
        ),
        decoration: ShapeDecoration(
          color: selected ? colors.selectedFill : null,
          shape: StadiumBorder(
            side: BorderSide(
              color: colors.ink,
              width: XpSpace.hairline(context) * 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: type.chip.copyWith(
            color: selected ? colors.onSelectedFill : colors.ink,
          ),
        ),
      ),
    );
  }
}
