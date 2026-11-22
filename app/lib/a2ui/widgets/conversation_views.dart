import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Tone of a [SavedNoteView], the catalog's `tone`.
enum NoteTone {
  /// After a save.
  ok,

  /// A fact.
  info,

  /// A problem.
  warn,
}

/// The catalog `SavedNote`: one confirmation line, announced politely.
class SavedNoteView extends StatelessWidget {
  /// Creates a note.
  const new({required this.text, this.tone = NoteTone.ok, super.key});

  /// The line.
  final String text;

  /// Tone.
  final NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final color = switch (tone) {
      NoteTone.ok => colors.income,
      NoteTone.info => colors.inkSecondary,
      NoteTone.warn => colors.danger,
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        children: [
          if (tone == NoteTone.ok)
            XpIcon(XpGlyph.check, size: XpSpace.iconRow, color: color)
          else
            Dot(color: color),
          const SizedBox(width: XpSpace.s8),
          Expanded(
            child: Text(
              text,
              style: type.subhead.copyWith(
                color: tone == NoteTone.warn ? colors.danger : colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a [NudgeView] is about, the catalog's `kind`.
enum NudgeTopic {
  /// A bill.
  bill,

  /// A budget.
  budget,

  /// A loan.
  loan,

  /// The exchange rate.
  rate,

  /// A report.
  report,

  /// Anything else.
  info,
}

/// The catalog `Nudge`: the Signal nudge row (dot, one line, one action);
/// without an action, just the line.
class NudgeView extends StatelessWidget {
  /// Creates a nudge.
  const new({
    required this.text,
    required this.topic,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// The line.
  final String text;

  /// Topic, spoken before the line.
  final NudgeTopic topic;

  /// Label of the action.
  final String? actionLabel;

  /// The action; null hides or disables it.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spoken = switch (topic) {
      NudgeTopic.bill => l10n.a2uiNudgeBill,
      NudgeTopic.budget => l10n.a2uiNudgeBudget,
      NudgeTopic.loan => l10n.a2uiNudgeLoan,
      NudgeTopic.rate => l10n.a2uiNudgeRate,
      NudgeTopic.report => l10n.a2uiNudgeReport,
      NudgeTopic.info => l10n.a2uiNudgeInfo,
    };
    final label = actionLabel;
    return Semantics(
      container: true,
      label: spoken,
      child: label != null
          ? NudgeRow(message: text, actionLabel: label, onAction: onAction)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Hairline(),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: XpSpace.minTarget,
                  ),
                  child: Row(
                    children: [
                      Dot(
                        color: XpColors.of(context).accent,
                        size: XpSpace.dotNudge,
                      ),
                      const SizedBox(width: XpSpace.s12),
                      Expanded(
                        child: Text(text, style: XpType.of(context).caption),
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

/// What a [NoticeView] reports, the catalog's `kind`.
enum NoticeTopic {
  /// No connection.
  offline,

  /// A usage limit.
  limit,

  /// The privacy mode.
  privacy,

  /// Anything else.
  error,
}

/// The catalog `Notice`: an error or limit in plain words, between
/// hairlines, with at most one action.
class NoticeView extends StatelessWidget {
  /// Creates a notice.
  const new({
    required this.text,
    required this.topic,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// One or two sentences.
  final String text;

  /// Topic.
  final NoticeTopic topic;

  /// Label of the action.
  final String? actionLabel;

  /// The action; null hides or disables it.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final glyph = switch (topic) {
      NoticeTopic.offline => XpGlyph.offline,
      NoticeTopic.privacy => XpGlyph.lock,
      NoticeTopic.limit => XpGlyph.bell,
      NoticeTopic.error => XpGlyph.close,
    };
    final color = topic == NoticeTopic.error ? colors.danger : colors.ink;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Hairline(),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: XpSpace.s12,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                XpIcon(glyph, size: XpSpace.iconRow, color: color),
                const SizedBox(width: XpSpace.s12),
                Expanded(child: Text(text, style: type.caption)),
              ],
            ),
          ),
          if (actionLabel != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: XpButton.text(label: actionLabel!, onPressed: onAction),
            ),
          const Hairline(),
        ],
      ),
    );
  }
}

/// One suggestion of [SuggestionChipsView].
final class Suggestion {
  /// Creates a suggestion.
  const new({required this.label, required this.message});

  /// Chip text.
  final String label;

  /// The text sent as the next capture.
  final String message;
}

/// The catalog `SuggestionChips`: at most four outline chips; a tap sends
/// the suggestion's message as the member's next text.
class SuggestionChipsView extends StatelessWidget {
  /// Creates the chips.
  const new({required this.options, required this.onPick, super.key});

  /// Most chips shown (A2UI_CATALOG 3.4).
  static const int maxChips = 4;

  /// The suggestions.
  final List<Suggestion> options;

  /// Sends a message; null disables the chips (a turn is streaming).
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: XpSpace.s8,
    runSpacing: XpSpace.s8,
    children: [
      for (final option in options.take(maxChips))
        XpChip(
          label: option.label,
          onPressed: onPick == null ? null : () => onPick!(option.message),
        ),
    ],
  );
}

/// The catalog `Transcript`: what the phone heard or read, quoted, with
/// the recording length for voice.
class TranscriptView extends StatelessWidget {
  /// Creates a transcript.
  const new({required this.text, this.seconds, super.key});

  /// The words.
  final String text;

  /// Recording length in seconds.
  final int? seconds;

  @override
  Widget build(BuildContext context) {
    final s = seconds;
    return Semantics(
      label: context.l10n.a2uiTranscriptHeard(text),
      excludeSemantics: true,
      child: TranscriptQuote(
        text: text,
        duration: s == null
            ? null
            : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
      ),
    );
  }
}
