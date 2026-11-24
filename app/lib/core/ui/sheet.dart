import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/buttons.dart';
import 'package:xpense_app/core/ui/controls.dart';
import 'package:xpense_app/core/ui/glass/glass_surface.dart';
import 'package:xpense_app/core/ui/money_text.dart';
import 'package:xpense_app/core/ui/rows.dart';

/// Heights a [GlassSheet] presents at (iOS detents).
enum SheetDetent {
  /// About half the screen.
  medium,

  /// Nearly full height, below the status bar.
  large,
}

/// Form header for a sheet: Cancel leading, title, action trailing
/// (DESIGN_SYSTEM 8.1; iOS review item 5).
@immutable
class SheetHeader {
  /// Creates a sheet header.
  const new({
    required this.cancelLabel,
    required this.onCancel,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  /// "Cancel".
  final String cancelLabel;

  /// Dismisses without saving.
  final VoidCallback onCancel;

  /// Sheet title.
  final String? title;

  /// Trailing action, such as "Save".
  final String? actionLabel;

  /// Trailing action handler.
  final VoidCallback? onAction;
}

/// A glass bottom sheet with a grabber (DESIGN_SYSTEM 8.1). Content inside
/// is solid text on the sheet's tinted glass; never another glass control.
class GlassSheet extends StatelessWidget {
  /// Creates a sheet.
  const new({
    required this.child,
    this.header,
    this.overMedia = false,
    super.key,
  });

  /// Sheet content.
  final Widget child;

  /// Optional form header.
  final SheetHeader? header;

  /// Whether the sheet sits over the camera (black shadow).
  final bool overMedia;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return GlassSurface(
      variant: GlassVariant.sheet,
      overMedia: overMedia,
      shape: const RoundedSuperellipseBorder(borderRadius: XpRadius.sheetAll),
      padding: const EdgeInsetsDirectional.fromSTEB(
        XpSpace.s20,
        XpSpace.s8,
        XpSpace.s20,
        XpSpace.s20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ExcludeSemantics(
              child: SizedBox(
                width: XpSpace.grabberWidth,
                height: XpSpace.grabberHeight,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colors.ink.withValues(alpha: XpOpacity.grabber),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: XpSpace.s8),
          if (header != null)
            Row(
              children: [
                XpButton.text(
                  label: header!.cancelLabel,
                  onPressed: header!.onCancel,
                ),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      header!.title ?? '',
                      textAlign: TextAlign.center,
                      style: type.title,
                    ),
                  ),
                ),
                if (header!.actionLabel != null)
                  XpButton.text(
                    label: header!.actionLabel!,
                    onPressed: header!.onAction,
                  )
                else
                  const SizedBox(width: XpSpace.minTarget),
              ],
            ),
          Flexible(child: child),
        ],
      ),
    );
  }
}

/// Presents [builder]'s content in a [GlassSheet] at [detent].
///
/// With [useRootNavigator], the sheet covers the whole app, the tab bar
/// too, when shown from a tab (WP-24).
///
/// [enableDrag] false stops a swipe down from closing the sheet: the drag
/// pops the route with `Navigator.pop`, which a `PopScope` inside cannot
/// stop, so a sheet that saves sets it false and guards Cancel and the
/// dimmed screen with a `PopScope` while it saves. [isDismissible] false
/// makes a tap on the dimmed screen do nothing at all.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  SheetDetent detent = SheetDetent.medium,
  SheetHeader? header,
  bool overMedia = false,
  bool useRootNavigator = false,
  bool enableDrag = true,
  bool isDismissible = true,
}) {
  final colors = XpColors.of(context);
  final motion = XpMotion.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    useSafeArea: true,
    backgroundColor: colors.canvas.withValues(alpha: 0),
    elevation: 0,
    barrierColor: colors.ink.withValues(alpha: XpOpacity.barrier),
    sheetAnimationStyle: AnimationStyle(
      duration: motion.slow,
      reverseDuration: motion.base,
      curve: XpMotion.slowCurve,
    ),
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      final height = detent == SheetDetent.large
          ? size.height
          : size.height / 2;
      return Padding(
        padding: EdgeInsetsDirectional.only(
          start: XpSpace.sheetMargin,
          end: XpSpace.sheetMargin,
          bottom: XpSpace.sheetMargin + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height),
          child: GlassSheet(
            header: header,
            overMedia: overMedia,
            child: Builder(builder: builder),
          ),
        ),
      );
    },
  );
}

/// One category group on a [ReceiptSheet].
@immutable
class ReceiptGroup {
  /// Creates a group row.
  const new({
    required this.name,
    required this.items,
    required this.minorUnits,
  });

  /// Category name.
  final String name;

  /// Item count text, such as "3 items".
  final String items;

  /// Group total in minor units.
  final int minorUnits;
}

/// Receipt result: merchant, total, split switch, group rows, Retake and
/// Save (DESIGN_SYSTEM 8.2, Receipt artboard). Goes inside a [GlassSheet].
class ReceiptSheet extends StatelessWidget {
  /// Creates the receipt sheet content.
  const new({
    required this.merchant,
    required this.meta,
    required this.totalMinor,
    required this.currency,
    required this.exponent,
    required this.splitLabel,
    required this.split,
    required this.onSplitChanged,
    required this.groups,
    required this.retakeLabel,
    required this.onRetake,
    required this.saveLabel,
    required this.onSave,
    this.converted,
    super.key,
  });

  /// Merchant name.
  final String merchant;

  /// Mono meta line such as "Today 18:05 · Cash"; upper-cased here.
  final String meta;

  /// Total in minor units.
  final int totalMinor;

  /// Currency code.
  final String currency;

  /// Decimal places of the currency.
  final int exponent;

  /// Converted total such as "≈ USD 35.50".
  final String? converted;

  /// "Split by category".
  final String splitLabel;

  /// Whether the receipt is split by category.
  final bool split;

  /// Toggles splitting.
  final ValueChanged<bool> onSplitChanged;

  /// Category groups.
  final List<ReceiptGroup> groups;

  /// "Retake".
  final String retakeLabel;

  /// Retakes the photo.
  final VoidCallback onRetake;

  /// "Save 3 entries →".
  final String saveLabel;

  /// Saves.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _build(
      context,
      stack:
          rowsStack(context) || XpSpace.isNarrow(context, constraints.maxWidth),
    ),
  );

  Widget _build(BuildContext context, {required bool stack}) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final merchantBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(merchant, style: type.title),
        Text(
          meta.toUpperCase(),
          style: type.monoLabel.copyWith(
            color: colors.inkSecondary,
            letterSpacing: 0,
          ),
        ),
      ],
    );
    final total = MoneyText(
      totalMinor,
      exponent: exponent,
      currency: currency,
      style: MoneyStyle.medium,
      converted: converted,
      textAlign: stack ? TextAlign.start : TextAlign.end,
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stack)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [merchantBlock, total],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: merchantBlock),
                total,
              ],
            ),
          const SizedBox(height: XpSpace.s8),
          Row(
            children: [
              Expanded(child: Text(splitLabel, style: type.subhead)),
              XpSwitch(
                value: split,
                onChanged: onSplitChanged,
                semanticLabel: splitLabel,
              ),
            ],
          ),
          for (final group in groups) ...[
            const Hairline(),
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: XpSpace.receiptGroupRow,
              ),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Text(group.name, style: type.subhead),
                    const SizedBox(width: XpSpace.s8),
                    Expanded(
                      child: Text(
                        group.items,
                        style: type.meta.copyWith(color: colors.inkSecondary),
                      ),
                    ),
                    MoneyText(group.minorUnits, exponent: exponent),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: XpSpace.s16),
          if (stack) ...[
            XpButton.primary(label: saveLabel, onPressed: onSave),
            const SizedBox(height: XpSpace.s8),
            XpButton.secondary(label: retakeLabel, onPressed: onRetake),
          ] else
            Row(
              children: [
                Expanded(
                  child: XpButton.secondary(
                    label: retakeLabel,
                    onPressed: onRetake,
                  ),
                ),
                const SizedBox(width: XpSpace.s12),
                Expanded(
                  flex: 2,
                  child: XpButton.primary(label: saveLabel, onPressed: onSave),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
