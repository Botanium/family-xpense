import 'package:cupertino_ui/cupertino_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/sheet.dart';

/// One action of [XpMenu], [showXpActionSheet] or [XpContextMenu].
@immutable
class XpAction {
  /// Creates an action.
  const new({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  /// Action text.
  final String label;

  /// Handler.
  final VoidCallback onPressed;

  /// Whether the action destroys data (drawn in `danger`).
  final bool destructive;
}

/// The system pull-down menu around a trigger (DESIGN_SYSTEM 8.1, menus).
class XpMenu extends StatelessWidget {
  /// Creates a pull-down menu.
  const new({required this.actions, required this.builder, super.key});

  /// Menu actions.
  final List<XpAction> actions;

  /// Builds the trigger; call `open` to show the menu.
  final Widget Function(BuildContext context, VoidCallback open) builder;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return CupertinoMenuAnchor(
      menuChildren: [
        for (final action in actions)
          CupertinoMenuItem(
            onPressed: action.onPressed,
            isDestructiveAction: action.destructive,
            child: Text(
              action.label,
              style: type.body.copyWith(
                color: action.destructive ? colors.danger : colors.ink,
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => builder(context, () {
        if (controller.isOpen) {
          controller.close();
        } else {
          controller.open();
        }
      }),
    );
  }
}

/// Shows the system action sheet; destructive options use `danger`.
Future<void> showXpActionSheet({
  required BuildContext context,
  required List<XpAction> actions,
  required String cancelLabel,
  String? title,
}) {
  final colors = XpColors.of(context);
  final type = XpType.of(context);
  return showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      actions: [
        for (final action in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: action.destructive,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              action.onPressed();
            },
            child: Text(
              action.label,
              style: type.body.copyWith(
                color: action.destructive ? colors.danger : colors.ink,
              ),
            ),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(sheetContext).pop(),
        child: Text(
          cancelLabel,
          style: type.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

/// Shows the system date picker in a glass sheet with Cancel and Done.
/// Returns the picked date, or null when cancelled.
Future<DateTime?> showXpDatePickerSheet({
  required BuildContext context,
  required DateTime initial,
  required String cancelLabel,
  required String doneLabel,
  String? title,
  CupertinoDatePickerMode mode = CupertinoDatePickerMode.date,
}) {
  var picked = initial;
  return showGlassSheet<DateTime>(
    context: context,
    header: SheetHeader(
      cancelLabel: cancelLabel,
      onCancel: () => Navigator.of(context).pop(),
      title: title,
      actionLabel: doneLabel,
      onAction: () => Navigator.of(context).pop(picked),
    ),
    builder: (context) => SizedBox(
      height: XpSpace.listRow * 4,
      child: CupertinoDatePicker(
        initialDateTime: initial,
        mode: mode,
        onDateTimeChanged: (value) => picked = value,
      ),
    ),
  );
}

/// The system context menu on a row: long-press shows the row lifted with
/// actions such as Edit, Duplicate and Delete (DESIGN_SYSTEM 8.1).
class XpContextMenu extends StatelessWidget {
  /// Creates a context menu around [child].
  const new({required this.actions, required this.child, super.key});

  /// Menu actions.
  final List<XpAction> actions;

  /// The row.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return CupertinoContextMenu.builder(
      actions: [
        for (final action in actions)
          CupertinoContextMenuAction(
            isDestructiveAction: action.destructive,
            onPressed: () {
              Navigator.of(context, rootNavigator: true).pop();
              action.onPressed();
            },
            child: Text(
              action.label,
              style: TextStyle(
                color: action.destructive ? colors.danger : colors.ink,
              ),
            ),
          ),
      ],
      builder: (context, animation) =>
          ColoredBox(color: colors.canvas, child: child),
    );
  }
}
