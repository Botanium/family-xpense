import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';

/// Keeps at most one row of a list swiped open: opening one closes the
/// others, and a scroll closes them all.
final class SwipeGroup extends ValueNotifier<Object?> {
  /// Creates a group with no row open.
  new() : super(null);

  /// Closes whichever row is open.
  void closeAll() => value = null;
}

/// One button revealed under a swiped row.
@immutable
final class SwipeAction {
  /// Creates the action.
  const new({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  /// Button text, such as "Delete".
  final String label;

  /// Handler; the row closes first.
  final VoidCallback onPressed;

  /// Whether it destroys data (drawn on `danger`).
  final bool destructive;
}

/// A row that slides toward its start edge to reveal [actions] at its end
/// (iOS list swipe actions, DESIGN_SYSTEM screen 16). A long swipe runs
/// [onFullSwipe] (Delete) without a second tap. While open, a tap on the
/// row closes it instead of opening the row.
///
/// Swiping is invisible to VoiceOver; the row adds the same actions as
/// custom semantics actions.
class SwipeActions extends StatefulWidget {
  /// Creates the row.
  const new({
    required this.id,
    required this.group,
    required this.actions,
    required this.child,
    this.onFullSwipe,
    super.key,
  });

  /// Which row this is in [group].
  final Object id;

  /// The list's group.
  final SwipeGroup group;

  /// Buttons, start to end.
  final List<SwipeAction> actions;

  /// What a swipe past most of the width does.
  final VoidCallback? onFullSwipe;

  /// The row.
  final Widget child;

  /// Width of one revealed button.
  static const double actionWidth = 80;

  /// How far, as a share of the width, a swipe must go to run
  /// [onFullSwipe].
  static const double fullSwipeShare = 0.6;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  // How far the row has moved toward its start edge, in logical pixels
  // (0 is closed; positive is open).
  late final AnimationController _shift = AnimationController.unbounded(
    vsync: this,
  );
  double _width = 0;

  double get _reveal => SwipeActions.actionWidth * widget.actions.length;

  @override
  void initState() {
    super.initState();
    widget.group.addListener(_onGroup);
  }

  @override
  void didUpdateWidget(SwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      oldWidget.group.removeListener(_onGroup);
      widget.group.addListener(_onGroup);
    }
  }

  @override
  void dispose() {
    widget.group.removeListener(_onGroup);
    _shift.dispose();
    super.dispose();
  }

  void _onGroup() {
    if (widget.group.value != widget.id && _shift.value != 0) _settle(0);
  }

  void _settle(double to) {
    final duration = XpMotion.of(context).base;
    if (duration == Duration.zero) {
      _shift.value = to;
      return;
    }
    _shift.animateTo(to, duration: duration, curve: XpMotion.baseCurve);
  }

  // Positive when the finger moves toward the start edge.
  double _towardStart(double dx) =>
      Directionality.of(context) == TextDirection.rtl ? dx : -dx;

  void _onStart(DragStartDetails details) {
    _shift.stop();
    widget.group.value = widget.id;
  }

  void _onUpdate(DragUpdateDetails details) {
    final max = widget.onFullSwipe == null ? _reveal * 1.2 : _width;
    _shift.value = (_shift.value + _towardStart(details.primaryDelta ?? 0))
        .clamp(0, max);
  }

  void _onEnd(DragEndDetails details) {
    final velocity = _towardStart(details.primaryVelocity ?? 0);
    final full = widget.onFullSwipe;
    if (full != null && _shift.value > _width * SwipeActions.fullSwipeShare) {
      _close();
      full();
      return;
    }
    final open =
        velocity > 300 || (velocity > -300 && _shift.value > _reveal / 2);
    _settle(open ? _reveal : 0);
    if (!open && widget.group.value == widget.id) widget.group.closeAll();
  }

  void _close() {
    _settle(0);
    if (widget.group.value == widget.id) widget.group.closeAll();
  }

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          // The row offers its actions to VoiceOver itself.
          excludeFromSemantics: true,
          onHorizontalDragStart: _onStart,
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _shift,
              child: ColoredBox(color: colors.canvas, child: widget.child),
              builder: (context, row) {
                final shift = _shift.value;
                if (shift == 0) return row!;
                final rtl = Directionality.of(context) == TextDirection.rtl;
                return Stack(
                  children: [
                    PositionedDirectional(
                      top: 0,
                      bottom: 0,
                      end: 0,
                      width: shift,
                      child: Row(
                        children: [
                          for (final action in widget.actions)
                            Expanded(
                              child: _ActionButton(
                                action: action,
                                onPressed: () {
                                  _close();
                                  action.onPressed();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(rtl ? shift : -shift, 0),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                        child: AbsorbPointer(child: row),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const new({required this.action, required this.onPressed});

  final SwipeAction action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final fill = action.destructive ? colors.danger : colors.controlWell;
    // `danger` is a dark red in light mode and a light red in dark mode;
    // `onPrimaryFill` is the matching light or dark label colour.
    final ink = action.destructive ? colors.onPrimaryFill : colors.ink;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ColoredBox(
          color: fill,
          child: Center(
            child: Text(
              action.label,
              textAlign: TextAlign.center,
              style: type.subhead.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
