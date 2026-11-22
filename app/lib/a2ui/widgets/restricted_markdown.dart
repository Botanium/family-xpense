import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Base style of a [RestrictedMarkdown].
enum TextVariant {
  /// Body text in ink.
  body,

  /// Smaller text in secondary ink.
  caption,
}

/// The text style a `Button` gives its `Text` child, so a label takes the
/// button's colour and weight instead of body text.
class ButtonLabelStyle extends InheritedWidget {
  /// Creates the scope.
  const new({required this.style, required super.child, super.key});

  /// The label style.
  final TextStyle style;

  /// The nearest label style, if inside a button.
  static TextStyle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ButtonLabelStyle>()?.style;

  @override
  bool updateShouldNotify(ButtonLabelStyle oldWidget) =>
      style != oldWidget.style;
}

/// Text with the Markdown subset the catalog allows (A2UI_CATALOG 3.1):
/// **bold**, *italic* and lists; a `## ` line is a section label. Nothing
/// else is interpreted: links show their words only, images their alt
/// text, and code its contents, so a surface can never open a URL or load
/// remote content (A2UI_CATALOG 2 rule 4).
class RestrictedMarkdown extends StatelessWidget {
  /// Renders [text] in [variant].
  const new(this.text, {this.variant = TextVariant.body, super.key});

  /// The source text.
  final String text;

  /// Base style.
  final TextVariant variant;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final label = ButtonLabelStyle.maybeOf(context);
    if (label != null) {
      return Text.rich(
        TextSpan(children: inlineSpans(text.replaceAll('\n', ' '))),
        style: label,
        textAlign: TextAlign.center,
      );
    }
    final base = switch (variant) {
      TextVariant.body => type.body,
      TextVariant.caption => type.caption.copyWith(color: colors.inkSecondary),
    };
    final blocks = parseBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, block) in blocks.indexed) ...[
          if (i > 0) const SizedBox(height: XpSpace.s8),
          switch (block) {
            HeadingBlock(:final text) => SectionLabel(text),
            ParagraphBlock(:final text) => Text.rich(
              TextSpan(children: inlineSpans(text)),
              style: base,
            ),
            ListItemBlock(:final marker, :final text) => MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: XpSpace.s20,
                    child: Text(marker, style: base),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: inlineSpans(text)),
                      style: base,
                    ),
                  ),
                ],
              ),
            ),
          },
        ],
      ],
    );
  }
}

/// One block of [RestrictedMarkdown].
sealed class MarkdownBlock {
  const new();
}

/// A `## ` line.
final class HeadingBlock extends MarkdownBlock {
  /// Creates a heading.
  const new(this.text);

  /// The words.
  final String text;
}

/// Consecutive plain lines.
final class ParagraphBlock extends MarkdownBlock {
  /// Creates a paragraph.
  const new(this.text);

  /// The words.
  final String text;
}

/// A `- ` or `1. ` line.
final class ListItemBlock extends MarkdownBlock {
  /// Creates a list item.
  const new(this.marker, this.text);

  /// `•` or the number with its point.
  final String marker;

  /// The words.
  final String text;
}

final RegExp _heading = RegExp(r'^\s*#{1,6}\s+(.*)$');
final RegExp _bullet = RegExp(r'^\s*[-*•+]\s+(.*)$');
final RegExp _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');

/// Splits [text] into blocks.
List<MarkdownBlock> parseBlocks(String text) {
  final blocks = <MarkdownBlock>[];
  final paragraph = <String>[];
  void flush() {
    if (paragraph.isEmpty) return;
    blocks.add(ParagraphBlock(paragraph.join(' ')));
    paragraph.clear();
  }

  for (final line in text.split('\n')) {
    if (line.trim().isEmpty) {
      flush();
    } else if (_heading.firstMatch(line) case final m?) {
      flush();
      blocks.add(HeadingBlock(m.group(1)!.trim()));
    } else if (_bullet.firstMatch(line) case final m?) {
      flush();
      blocks.add(ListItemBlock('•', m.group(1)!.trim()));
    } else if (_numbered.firstMatch(line) case final m?) {
      flush();
      blocks.add(ListItemBlock('${m.group(1)}.', m.group(2)!.trim()));
    } else {
      paragraph.add(line.trim());
    }
  }
  flush();
  return blocks;
}

final RegExp _inline = RegExp(
  r'!\[([^\]]*)\]\([^)]*\)'
  r'|\[([^\]]*)\]\([^)]*\)'
  r'|\*\*(.+?)\*\*'
  r'|(?<!\w)__(.+?)__(?!\w)'
  r'|(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])'
  r'|(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)'
  '|`([^`]*)`',
);

/// The spans of one line: bold and italic styled, everything else plain.
List<InlineSpan> inlineSpans(String text) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    final bold = m.group(3) ?? m.group(4);
    final italic = m.group(5) ?? m.group(6);
    if (bold != null) {
      spans.add(
        TextSpan(
          text: bold,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      );
    } else if (italic != null) {
      spans.add(
        TextSpan(
          text: italic,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
      );
    } else {
      // An image's alt text, a link's words or code: plain.
      final plain = m.group(1) ?? m.group(2) ?? m.group(7) ?? '';
      if (plain.isNotEmpty) spans.add(TextSpan(text: plain));
    }
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}
