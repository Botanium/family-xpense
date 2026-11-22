import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/badges.dart';
import 'package:xpense_app/core/ui/xp_icon.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// Whether rows with a trailing figure should stack it under the label.
bool rowsStack(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= XpFonts.stackRowsFromScale;

/// A one-hairline separator (one physical pixel; two under Increase
/// Contrast).
class Hairline extends StatelessWidget {
  /// Creates a hairline in the `hairline` colour.
  const new({this.soft = false, super.key});

  /// Whether to use the softer list-row colour.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return SizedBox(
      height: XpSpace.hairline(context),
      width: double.infinity,
      child: ColoredBox(color: soft ? colors.hairlineSoft : colors.hairline),
    );
  }
}

/// Dot, label, dotted leader, mono value (DESIGN_SYSTEM 8.2, Home ledger).
class LedgerRow extends StatelessWidget {
  /// Creates a ledger row.
  const new({
    required this.label,
    required this.value,
    this.dotColor,
    this.valueColor,
    super.key,
  });

  /// Label, such as "Income".
  final String label;

  /// Mono value, such as "5,650.00".
  final String value;

  /// Colour of the leading dot; null hides it.
  final Color? dotColor;

  /// Colour of the value; defaults to ink.
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final labelText = Text(label, style: type.subhead);
    final valueText = Text(
      value,
      style: type.figureBody.copyWith(color: valueColor ?? colors.ink),
    );
    final dot = dotColor == null
        ? null
        : Padding(
            padding: const EdgeInsetsDirectional.only(end: XpSpace.s8),
            child: Dot(color: dotColor!),
          );
    return MergeSemantics(
      child: rowsStack(context)
          ? Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                vertical: XpSpace.s4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ?dot,
                      Flexible(child: labelText),
                    ],
                  ),
                  valueText,
                ],
              ),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: XpSpace.ledgerRow),
              child: Row(
                children: [
                  ?dot,
                  labelText,
                  const SizedBox(width: XpSpace.s8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: XpSpace.s8,
                      ),
                      child: CustomPaint(
                        size: const Size.fromHeight(XpSpace.s2),
                        painter: _LeaderPainter(
                          color: colors.leader,
                          width: XpSpace.hairline(context) * 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: XpSpace.s8),
                  valueText,
                ],
              ),
            ),
    );
  }
}

class _LeaderPainter extends CustomPainter {
  const new({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    const step = XpSpace.s4;
    final y = size.height / 2;
    for (var x = width; x < size.width; x += step) {
      canvas.drawLine(Offset(x, y), Offset(x, y), paint);
    }
  }

  @override
  bool shouldRepaint(_LeaderPainter old) =>
      old.color != color || old.width != width;
}

/// A list row: title, optional subtitle, optional trailing figure, soft
/// hairline under it (DESIGN_SYSTEM 8.1). No grouped boxes.
class XpListRow extends StatelessWidget {
  /// Creates a list row.
  const new({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  /// Row title.
  final String title;

  /// Meta line under the title.
  final String? subtitle;

  /// Leading widget, such as a [Dot].
  final Widget? leading;

  /// Trailing widget, usually a `MoneyText`.
  final Widget? trailing;

  /// Tap handler; null makes the row static.
  final VoidCallback? onTap;

  /// Whether to draw the soft hairline under the row.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final stack = rowsStack(context) && trailing != null;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: type.bodyStrong),
        if (subtitle != null)
          Text(
            subtitle!,
            style: type.meta.copyWith(color: colors.inkSecondary),
          ),
        if (stack) trailing!,
      ],
    );
    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: XpSpace.listRow),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: XpSpace.s8),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: XpSpace.s12),
            ],
            Expanded(child: texts),
            if (!stack && trailing != null) ...[
              const SizedBox(width: XpSpace.s12),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap != null) {
      row = XpPressable(onPressed: onTap, child: row);
    }
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [row, if (showDivider) const Hairline(soft: true)],
      ),
    );
  }
}

/// Section header: caption in secondary ink with an optional trailing link
/// such as "See all" (DESIGN_SYSTEM 8.1).
class SectionLabel extends StatelessWidget {
  /// Creates a section label.
  const new(this.label, {this.actionLabel, this.onAction, super.key});

  /// Section name.
  final String label;

  /// Trailing link text.
  final String? actionLabel;

  /// Trailing link handler.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              label,
              style: type.caption.copyWith(color: colors.inkSecondary),
            ),
          ),
        ),
        if (actionLabel != null)
          XpPressable(
            onPressed: onAction,
            child: Text(
              actionLabel!,
              style: type.caption.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
      ],
    );
  }
}

/// A section of rows under a [SectionLabel]; hairlines, never a box.
class XpSection extends StatelessWidget {
  /// Creates a section.
  const new({
    required this.label,
    required this.children,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Section name.
  final String label;

  /// Rows.
  final List<Widget> children;

  /// Trailing link text.
  final String? actionLabel;

  /// Trailing link handler.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SectionLabel(label, actionLabel: actionLabel, onAction: onAction),
      ...children,
    ],
  );
}

/// A settings row with a chevron (DESIGN_SYSTEM 8.1).
class XpDisclosure extends StatelessWidget {
  /// Creates a disclosure row.
  const new({
    required this.title,
    required this.onTap,
    this.value,
    this.showDivider = true,
    super.key,
  });

  /// Row title.
  final String title;

  /// Current value, shown before the chevron.
  final String? value;

  /// Opens the detail.
  final VoidCallback? onTap;

  /// Whether to draw the soft hairline under the row.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        XpPressable(
          onPressed: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: XpSpace.listRow),
            child: Row(
              children: [
                Expanded(child: Text(title, style: type.body)),
                if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      style: type.body.copyWith(color: colors.inkSecondary),
                      textAlign: TextAlign.end,
                    ),
                  ),
                const SizedBox(width: XpSpace.s8),
                XpIcon(
                  XpGlyph.forward,
                  size: XpSpace.iconRow,
                  color: colors.inkSecondary,
                ),
              ],
            ),
          ),
        ),
        if (showDivider) const Hairline(soft: true),
      ],
    );
  }
}

/// Orange dot, one line, one text action, between hairlines
/// (DESIGN_SYSTEM 8.2, Home nudge).
class NudgeRow extends StatelessWidget {
  /// Creates a nudge row.
  const new({
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  /// One line, such as "Internet is usually paid by the 5th."
  final String message;

  /// Action text, such as "Add".
  final String actionLabel;

  /// Action handler.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Hairline(),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: XpSpace.s2),
          child: Row(
            children: [
              Dot(color: colors.accent, size: XpSpace.dotNudge),
              const SizedBox(width: XpSpace.s12),
              Expanded(child: Text(message, style: type.caption)),
              const SizedBox(width: XpSpace.s8),
              XpPressable(
                onPressed: onAction,
                child: Text(
                  actionLabel,
                  style: type.caption.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const Hairline(),
      ],
    );
  }
}

/// Who changed what, when, with a Restore action (DESIGN_SYSTEM 8.2).
class HistoryRow extends StatelessWidget {
  /// Creates a history row.
  const new({
    required this.title,
    required this.when,
    this.detail,
    this.restoreLabel,
    this.onRestore,
    super.key,
  });

  /// What happened, such as "Sam changed the amount".
  final String title;

  /// When, such as "TODAY 13:20"; shown in mono, upper-cased.
  final String when;

  /// The change itself, such as "10,000 → 12,000".
  final String? detail;

  /// Restore action text; null hides the action.
  final String? restoreLabel;

  /// Restores this version.
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: XpSpace.s8),
          child: Row(
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: type.bodyStrong),
                      if (detail != null)
                        Text(detail!, style: type.figureSmall),
                      Text(
                        when.toUpperCase(),
                        style: type.monoLabel.copyWith(
                          color: colors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (restoreLabel != null)
                XpPressable(
                  onPressed: onRestore,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const XpIcon(XpGlyph.restore, size: XpSpace.iconRow),
                      const SizedBox(width: XpSpace.s4),
                      Text(
                        restoreLabel!,
                        style: type.caption.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Hairline(soft: true),
      ],
    );
  }
}
