import 'package:flutter/widgets.dart';

import 'package:xpense_app/a2ui/xpense_actions.dart';

/// What every Xpense component can reach: the app's [XpenseActions], the
/// surface it renders in, and whether an agent turn is streaming.
///
/// `SurfaceView` provides it around each surface; widget tests and the
/// gallery provide it directly.
class XpenseScope extends InheritedWidget {
  /// Creates a scope.
  const new({
    required this.actions,
    required super.child,
    this.surfaceId = '',
    this.busy = false,
    super.key,
  });

  /// The app.
  final XpenseActions actions;

  /// The surface being rendered.
  final String surfaceId;

  /// Whether an agent turn is streaming: actions that would reach the
  /// agent are disabled and show a busy state (A2UI_CATALOG 5.2).
  final bool busy;

  /// The nearest scope.
  static XpenseScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<XpenseScope>();
    assert(scope != null, 'No XpenseScope above this Xpense component.');
    return scope!;
  }

  @override
  bool updateShouldNotify(XpenseScope oldWidget) =>
      actions != oldWidget.actions ||
      surfaceId != oldWidget.surfaceId ||
      busy != oldWidget.busy;
}
