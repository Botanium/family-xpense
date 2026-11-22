import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/buttons.dart';
import 'package:xpense_app/core/ui/glass/glass_surface.dart';
import 'package:xpense_app/core/ui/rows.dart';
import 'package:xpense_app/core/ui/xp_icon.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// Glass toast with one action, shown for ten seconds (DESIGN_SYSTEM 8.2).
class UndoToast extends StatelessWidget {
  /// Creates the toast.
  const new({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  /// What happened, such as "Entry deleted".
  final String message;

  /// "Undo".
  final String actionLabel;

  /// Undoes it.
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: GlassSurface(
        variant: GlassVariant.dock,
        padding: const EdgeInsetsDirectional.only(
          start: XpSpace.s20,
          end: XpSpace.s8,
        ),
        child: Row(
          children: [
            Expanded(
              child: Builder(
                builder: (context) => Text(
                  message,
                  style: type.subhead.copyWith(
                    color: GlassSurface.contentColorOf(context),
                  ),
                ),
              ),
            ),
            XpPressable(
              onPressed: onAction,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: XpSpace.s12,
                ),
                child: Text(
                  actionLabel,
                  style: type.subhead.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows an [UndoToast] above the bottom controls for
/// [XpMotion.toastLifetime]. Returns a function that dismisses it early.
VoidCallback showUndoToast({
  required BuildContext context,
  required String message,
  required String actionLabel,
  required VoidCallback onAction,
}) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  Timer? timer;
  var removed = false;
  void dismiss() {
    if (removed) return;
    removed = true;
    timer?.cancel();
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (context) => PositionedDirectional(
      start: XpSpace.floatingMargin,
      end: XpSpace.floatingMargin,
      bottom:
          XpSpace.bottomControlOffset(context) +
          XpSpace.tabBarHeight +
          XpSpace.s12,
      child: UndoToast(
        message: message,
        actionLabel: actionLabel,
        onAction: () {
          dismiss();
          onAction();
        },
      ),
    ),
  );
  overlay.insert(entry);
  timer = Timer(XpMotion.toastLifetime, dismiss);
  return dismiss;
}

/// One line and one action; no illustration (DESIGN_SYSTEM 8.2).
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const new({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// One line, such as "No entries yet."
  final String message;

  /// Action text, such as "Add one".
  final String? actionLabel;

  /// Action handler.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: XpSpace.s32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: type.body.copyWith(color: colors.inkSecondary),
          ),
          if (actionLabel != null)
            XpButton.text(label: actionLabel!, onPressed: onAction),
        ],
      ),
    );
  }
}

/// A hairline strip under the top bar while offline (DESIGN_SYSTEM 8.2).
class OfflineBanner extends StatelessWidget {
  /// Creates the banner.
  const new({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Such as "Offline. Showing saved data."
  final String message;

  /// Optional action, such as "Retry".
  final String? actionLabel;

  /// Action handler.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: XpSpace.screenMargin,
            ),
            child: Row(
              children: [
                XpIcon(
                  XpGlyph.offline,
                  size: XpSpace.iconRow,
                  color: colors.inkSecondary,
                ),
                const SizedBox(width: XpSpace.s8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      vertical: XpSpace.s8,
                    ),
                    child: Text(
                      message,
                      style: type.meta.copyWith(color: colors.inkSecondary),
                    ),
                  ),
                ),
                if (actionLabel != null)
                  XpPressable(
                    onPressed: onAction,
                    child: Text(
                      actionLabel!,
                      style: type.meta.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          const Hairline(),
        ],
      ),
    );
  }
}
