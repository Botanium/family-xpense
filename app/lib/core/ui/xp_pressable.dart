import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';

/// A tap target with iOS-style press feedback and full semantics.
///
/// Guarantees a 44 × 44 hit area around [child] whatever its visual size
/// (DESIGN_SYSTEM 5), dims while pressed, and announces itself as a button.
/// Every tappable component in `core/ui/` is built on it.
class XpPressable extends StatelessWidget {
  /// Creates a pressable.
  const new({
    required this.child,
    required this.onPressed,
    this.semanticLabel,
    this.selected,
    this.toggled,
    this.excludeChildSemantics = false,
    this.minSize = const Size.square(XpSpace.minTarget),
    super.key,
  });

  /// The visual content.
  final Widget child;

  /// Called on tap; null disables the target.
  final VoidCallback? onPressed;

  /// Spoken label; when null the child's own text is read.
  final String? semanticLabel;

  /// Selected state for chips and tabs; null when not selectable.
  final bool? selected;

  /// On or off state for switches; null when not a toggle.
  final bool? toggled;

  /// Whether to drop the child's semantics in favour of [semanticLabel].
  final bool excludeChildSemantics;

  /// Smallest hit area.
  final Size minSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: toggled == null,
      enabled: enabled,
      selected: selected,
      toggled: toggled,
      label: semanticLabel,
      excludeSemantics: excludeChildSemantics,
      onTap: onPressed,
      child: _PressFeedback(
        onPressed: onPressed,
        minSize: minSize,
        child: child,
      ),
    );
  }
}

class _PressFeedback extends StatefulWidget {
  const new({
    required this.child,
    required this.onPressed,
    required this.minSize,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Size minSize;

  @override
  State<_PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<_PressFeedback> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final motion = XpMotion.of(context);
    final opacity = !enabled
        ? XpOpacity.disabled
        : _down
        ? XpOpacity.pressed
        : 1.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: widget.onPressed,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minSize.width,
          minHeight: widget.minSize.height,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: AnimatedOpacity(
            opacity: opacity,
            duration: motion.fast,
            curve: XpMotion.fastCurve,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
