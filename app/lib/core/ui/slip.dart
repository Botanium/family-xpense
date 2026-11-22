import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/badges.dart';

/// The only raised content surface: an opaque, receipt-like slip with
/// dashed rules (DESIGN_SYSTEM 8.1, Ask artboard).
class Slip extends StatelessWidget {
  /// Creates a slip around [children], spaced 12 pt apart.
  const new({required this.children, this.semanticLabel, super.key});

  /// Slip content; use [DashedRule] between groups.
  final List<Widget> children;

  /// Spoken summary that replaces the children for screen readers, such as
  /// "Expense, dining out, 10,000 Iraqi dinars, today, guessed category".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: XpRadius.slipAll,
        boxShadow: XpElevation.of(context).slip,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          XpSpace.slipPadding,
          XpSpace.slipPadding,
          XpSpace.slipPadding,
          XpSpace.s16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, child) in children.indexed) ...[
              if (i > 0) const SizedBox(height: XpSpace.s12),
              child,
            ],
          ],
        ),
      ),
    );
    return Semantics(container: true, label: semanticLabel, child: body);
  }
}

/// The dashed perforation rule inside a slip.
class DashedRule extends StatelessWidget {
  /// Creates a dashed rule.
  const new({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.fromHeight(XpSpace.hairline(context) * 2),
      painter: _DashPainter(
        color: XpColors.of(context).perforation,
        width: XpSpace.hairline(context) * 2,
      ),
    ),
  );
}

class _DashPainter extends CustomPainter {
  const new({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;
    const dash = XpSpace.s4;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) =>
      old.color != color || old.width != width;
}

/// One field row on a slip: secondary label, mono value.
@immutable
class SlipField {
  /// Creates a field row.
  const new({required this.label, required this.value, this.guessed = false});

  /// Label, such as "Who".
  final String label;

  /// Value, such as "You + kids"; shown upper-case in mono.
  final String value;

  /// Whether the value was guessed (marks the row with a badge).
  final bool guessed;
}

/// A capture slip: mono header (intent · category, confidence), amount,
/// dashed rule, field rows, question, chips and save (DESIGN_SYSTEM 8.2).
class EntrySlip extends StatelessWidget {
  /// Creates an entry slip.
  const new({
    required this.header,
    required this.amount,
    this.confidence,
    this.fields = const [],
    this.guessedLabel,
    this.question,
    this.choices,
    this.action,
    this.footer,
    this.semanticLabel,
    super.key,
  });

  /// Header such as "Expense · Dining out"; upper-cased here.
  final String header;

  /// Confidence such as "94%".
  final String? confidence;

  /// The amount, usually a large `MoneyText` with a converted line.
  final Widget amount;

  /// Field rows.
  final List<SlipField> fields;

  /// Text of the guessed badge, such as "Guessed"; required when any field
  /// is guessed.
  final String? guessedLabel;

  /// Follow-up question.
  final String? question;

  /// Answers to [question], usually `ChoiceChips`.
  final Widget? choices;

  /// Save action, usually a primary `XpButton`.
  final Widget? action;

  /// Status line after saving.
  final Widget? footer;

  /// Spoken summary of the whole slip.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final label = type.monoLabel.copyWith(
      color: colors.inkSecondary,
      letterSpacing: 1,
    );
    return Slip(
      semanticLabel: semanticLabel,
      children: [
        Row(
          children: [
            Expanded(child: Text(header.toUpperCase(), style: label)),
            if (confidence != null) Text(confidence!, style: label),
          ],
        ),
        amount,
        if (fields.isNotEmpty) ...[
          const DashedRule(),
          for (final field in fields)
            Row(
              children: [
                Text(
                  field.label,
                  style: type.caption.copyWith(color: colors.inkSecondary),
                ),
                const SizedBox(width: XpSpace.s8),
                if (field.guessed && guessedLabel != null)
                  GuessedBadge(label: guessedLabel!),
                Expanded(
                  child: Text(
                    field.value.toUpperCase(),
                    style: type.figureSmall,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
        ],
        if (question != null || choices != null) const DashedRule(),
        if (question != null) Text(question!, style: type.subhead),
        ?choices,
        ?action,
        ?footer,
      ],
    );
  }
}
