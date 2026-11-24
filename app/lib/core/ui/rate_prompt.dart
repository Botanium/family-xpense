import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/badges.dart';
import 'package:xpense_app/core/ui/buttons.dart';
import 'package:xpense_app/core/ui/inputs.dart';
import 'package:xpense_app/core/ui/rows.dart';
import 'package:xpense_app/core/ui/sheet.dart';
import 'package:xpense_app/core/ui/system.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// Where a [RatePrompt] sits.
enum RatePromptPlacement {
  /// In Home's nudge slot: orange dot, between hairlines.
  home,

  /// Inside a slip: no dot, no rules.
  inline,
}

/// The daily exchange-rate question (DESIGN_SYSTEM 8.2, D-16): one line with
/// yesterday's rate in mono, **Same** as the primary text action and
/// **Change**, which opens a number pad sheet.
class RatePrompt extends StatelessWidget {
  /// Creates a rate prompt.
  const new({
    required this.question,
    required this.rate,
    required this.sameLabel,
    required this.changeLabel,
    required this.onSame,
    required this.onChange,
    this.placement = RatePromptPlacement.home,
    this.semanticLabel,
    super.key,
  });

  /// "Today's dollar rate?"
  final String question;

  /// Yesterday's rate as text, such as "1,705".
  final String rate;

  /// "Same".
  final String sameLabel;

  /// "Change".
  final String changeLabel;

  /// Keeps yesterday's rate.
  final VoidCallback onSame;

  /// Opens the number pad sheet (see [RateChangeSheet]).
  final VoidCallback onChange;

  /// Home nudge slot or inline on a slip.
  final RatePromptPlacement placement;

  /// Spoken question with the rate, such as "Today's dollar rate? Yesterday
  /// it was 1,705 dinars".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final home = placement == RatePromptPlacement.home;
    final line = Text.rich(
      TextSpan(
        text: '$question ',
        children: [TextSpan(text: rate, style: type.figureBody)],
      ),
      style: type.caption,
      semanticsLabel: semanticLabel,
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        XpPressable(
          onPressed: onChange,
          child: Text(
            changeLabel,
            style: type.caption.copyWith(color: colors.inkSecondary),
          ),
        ),
        const SizedBox(width: XpSpace.s16),
        XpPressable(
          onPressed: onSame,
          child: Text(
            sameLabel,
            style: type.caption.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    final stack = rowsStack(context);
    final body = stack
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: XpSpace.s8),
                child: line,
              ),
              actions,
            ],
          )
        : Row(
            children: [
              if (home) ...[
                Dot(color: colors.accent, size: XpSpace.dotNudge),
                const SizedBox(width: XpSpace.s12),
              ],
              Expanded(child: line),
              const SizedBox(width: XpSpace.s8),
              actions,
            ],
          );
    if (!home) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Hairline(),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: XpSpace.s2),
          child: body,
        ),
        const Hairline(),
      ],
    );
  }
}

/// Number pad content for changing today's rate; goes in a `GlassSheet`.
class RateChangeSheet extends StatefulWidget {
  /// Creates the sheet content.
  const new({
    required this.title,
    required this.initial,
    required this.unit,
    required this.saveLabel,
    required this.backspaceLabel,
    required this.onSave,
    super.key,
  });

  /// "Today's dollar rate".
  final String title;

  /// Starting text, usually yesterday's rate.
  final String initial;

  /// Unit after the figure, such as "IQD per USD".
  final String unit;

  /// "Save".
  final String saveLabel;

  /// Spoken label for the backspace key.
  final String backspaceLabel;

  /// Called with the typed rate as text (decimal string, never `double`).
  final ValueChanged<String> onSave;

  /// Most whole digits a rate can have; an IQD per USD rate needs four.
  static const int maxWholeDigits = 6;

  /// Most decimal digits a rate can have.
  static const int maxFractionDigits = 4;

  @override
  State<RateChangeSheet> createState() => _RateChangeSheetState();
}

class _RateChangeSheetState extends State<RateChangeSheet> {
  late String _text = _bounded(widget.initial);

  /// Keeps digits and the first point, within the digit limits.
  static String _bounded(String raw) {
    final buffer = StringBuffer();
    var whole = 0;
    var fraction = 0;
    var seenPoint = false;
    for (final char in raw.split('')) {
      if (char == '.' && !seenPoint) {
        seenPoint = true;
        buffer.write(char);
      } else if (RegExp(r'^\d$').hasMatch(char)) {
        if (!seenPoint && whole < RateChangeSheet.maxWholeDigits) {
          whole++;
          buffer.write(char);
        } else if (seenPoint && fraction < RateChangeSheet.maxFractionDigits) {
          fraction++;
          buffer.write(char);
        }
      }
    }
    return buffer.toString();
  }

  void _key(String key) {
    setState(() {
      if (key == XpNumberPad.backspace) {
        if (_text.isNotEmpty) _text = _text.substring(0, _text.length - 1);
      } else if (key == '.') {
        if (!_text.contains('.')) _text = _text.isEmpty ? '0.' : '$_text.';
      } else {
        final next = _text == '0' ? key : '$_text$key';
        // Ignore keys past the limit instead of truncating what was typed.
        if (_bounded(next) == next) _text = next;
      }
    });
  }

  /// Groups a digit string by thousands without parsing it as a number.
  static String _groupDigits(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  String get _display {
    if (_text.isEmpty) return '0';
    final dot = _text.indexOf('.');
    final whole = dot < 0 ? _text : _text.substring(0, dot);
    final rest = dot < 0 ? '' : _text.substring(dot);
    return '${whole.isEmpty ? '0' : _groupDigits(whole)}$rest';
  }

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: type.title, textAlign: TextAlign.center),
        const SizedBox(height: XpSpace.s12),
        Semantics(
          liveRegion: true,
          child: Text(
            _display,
            style: type.figureLarge,
            textAlign: TextAlign.center,
          ),
        ),
        Text(
          widget.unit.toUpperCase(),
          style: type.monoLabel.copyWith(color: colors.inkSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: XpSpace.s12),
        XpNumberPad(onKey: _key, backspaceLabel: widget.backspaceLabel),
        const SizedBox(height: XpSpace.s12),
        XpButton.primary(
          label: widget.saveLabel,
          onPressed: _text.isEmpty ? null : () => widget.onSave(_text),
        ),
      ],
    );
  }
}

/// [rate] (a decimal string such as `"1705"` or `"1507.5"`) grouped by
/// thousands for display, such as "1,705", without parsing it as a number.
String formatRate(String rate) {
  final dot = rate.indexOf('.');
  final whole = dot < 0 ? rate : rate.substring(0, dot);
  final rest = dot < 0 ? '' : rate.substring(dot);
  return '${_RateChangeSheetState._groupDigits(whole)}$rest';
}

/// The words [showRateEntry] uses.
@immutable
class RateEntryLabels {
  /// Creates the labels.
  const new({
    required this.title,
    required this.unit,
    required this.save,
    required this.backspace,
    required this.confirmTitle,
    required this.confirmSave,
    required this.confirmChange,
  });

  /// "Today's dollar rate".
  final String title;

  /// "IQD per USD".
  final String unit;

  /// "Save".
  final String save;

  /// Spoken label of the backspace key.
  final String backspace;

  /// The question when a typed rate is far from the previous one, given the
  /// typed rate as entered, such as "1,900 is more than 5% from 1,705.".
  final String Function(String typed) confirmTitle;

  /// The confirming action, given the typed rate, such as "Save 1,900".
  final String Function(String typed) confirmSave;

  /// The action that goes back to the keypad, such as "Change it".
  final String confirmChange;
}

/// Opens the rate keypad starting at [initial] and returns the rate typed
/// (a decimal string), or null when the person closed it.
///
/// When [needsConfirm] says the typed rate is suspicious (more than 5% from
/// the previous one, a typo guard), an action sheet asks first; going back
/// reopens the keypad with what was typed.
Future<String?> showRateEntry({
  required BuildContext context,
  required RateEntryLabels labels,
  required String initial,
  bool Function(String typed)? needsConfirm,
}) async {
  var start = initial;
  while (true) {
    final typed = await showGlassSheet<String>(
      context: context,
      // Over the tab bar when asked from Home.
      useRootNavigator: true,
      // The keypad needs more than half a small screen; the sheet still
      // only takes the height it needs.
      detent: SheetDetent.large,
      builder: (sheet) => RateChangeSheet(
        title: labels.title,
        initial: start,
        unit: labels.unit,
        saveLabel: labels.save,
        backspaceLabel: labels.backspace,
        onSave: (rate) => Navigator.of(sheet).pop(rate),
      ),
    );
    if (typed == null || !context.mounted) return null;
    if (!(needsConfirm?.call(typed) ?? false)) return typed;
    var confirmed = false;
    await showXpActionSheet(
      context: context,
      title: labels.confirmTitle(typed),
      actions: [
        XpAction(
          label: labels.confirmSave(typed),
          onPressed: () => confirmed = true,
        ),
      ],
      cancelLabel: labels.confirmChange,
    );
    if (confirmed) return typed;
    if (!context.mounted) return null;
    start = typed;
  }
}

/// The app's words for [showRateEntry]: [title] defaults to "Today's dollar
/// rate"; [previous] is the rate a typed one is compared with, as stored
/// (such as `"1705"`).
RateEntryLabels rateEntryLabelsOf(
  BuildContext context, {
  String? title,
  String? previous,
}) {
  final l10n = context.l10n;
  return RateEntryLabels(
    title: title ?? l10n.settingsFxRateTitle,
    unit: l10n.settingsFxRateUnit,
    save: l10n.settingsFxRateSave,
    backspace: l10n.settingsFxRateBackspace,
    confirmTitle: (typed) => l10n.settingsFxRateConfirmTitle(
      formatRate(typed),
      previous == null ? '' : formatRate(previous),
    ),
    confirmSave: (typed) => l10n.settingsFxRateConfirmSave(formatRate(typed)),
    confirmChange: l10n.settingsFxRateConfirmChange,
  );
}
