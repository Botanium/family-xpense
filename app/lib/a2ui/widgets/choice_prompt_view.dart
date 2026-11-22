import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/input_views.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// One answer of a [ChoicePromptView].
final class PromptAnswer {
  /// Creates an answer.
  const new({required this.label, required this.value, this.hint});

  /// What the member sees.
  final String label;

  /// What is written when picked.
  final String value;

  /// A short line shown under the chips when this answer is picked.
  final String? hint;
}

/// The catalog `ChoicePrompt`: one question with two to five chips, and
/// "Other…" with a text field when allowed. A pick is written locally; it
/// reaches the agent only through the component's own action.
class ChoicePromptView extends StatefulWidget {
  /// Creates the prompt.
  const new({
    required this.question,
    required this.answers,
    required this.onPick,
    this.selected,
    this.allowOther = false,
    super.key,
  });

  /// The question.
  final String question;

  /// The answers.
  final List<PromptAnswer> answers;

  /// The current value.
  final String? selected;

  /// Whether "Other…" is offered.
  final bool allowOther;

  /// Records a pick; null disables the chips.
  final ValueChanged<String>? onPick;

  @override
  State<ChoicePromptView> createState() => _ChoicePromptViewState();
}

class _ChoicePromptViewState extends State<ChoicePromptView> {
  bool _other = false;
  String _otherText = '';

  /// The member's pick. Picking the provisional value writes nothing new,
  /// so the prompt keeps its own record of the answer.
  String? _picked;

  @override
  void didUpdateWidget(ChoicePromptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != null && widget.selected != _picked) _picked = null;
  }

  void _pick(String value) {
    setState(() {
      _picked = value;
      _other = false;
    });
    widget.onPick!(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final selected = _picked ?? widget.selected;
    final picked = widget.answers.where((a) => a.value == selected).firstOrNull;
    final otherPicked =
        selected != null &&
        selected.isNotEmpty &&
        picked == null &&
        widget.allowOther;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(widget.question, style: type.subhead),
        ),
        const SizedBox(height: XpSpace.s8),
        Wrap(
          spacing: XpSpace.s8,
          runSpacing: XpSpace.s8,
          children: [
            for (final answer in widget.answers)
              XpChip(
                key: ValueKey('choice_${answer.value}'),
                label: answer.label,
                selected: answer.value == selected,
                onPressed: widget.onPick == null
                    ? null
                    : () {
                        unawaited(XpHaptics.picked());
                        _pick(answer.value);
                      },
              ),
            if (widget.allowOther)
              XpChip(
                key: const ValueKey('choice_other'),
                label: l10n.a2uiOther,
                selected: _other || otherPicked,
                onPressed: widget.onPick == null
                    ? null
                    : () => setState(() => _other = true),
              ),
          ],
        ),
        if (picked?.hint case final hint?)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: XpSpace.s6),
            child: Text(
              hint,
              style: type.meta.copyWith(color: colors.inkSecondary),
            ),
          ),
        if (_other) ...[
          const SizedBox(height: XpSpace.s8),
          CatalogTextField(
            label: l10n.a2uiOtherLabel,
            value: _otherText,
            onChanged: (text) => setState(() => _otherText = text),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: XpButton.text(
              label: l10n.a2uiDone,
              onPressed: _otherText.trim().isEmpty || widget.onPick == null
                  ? null
                  : () => _pick(_otherText.trim()),
            ),
          ),
        ],
      ],
    );
  }
}
