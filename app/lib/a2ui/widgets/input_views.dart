import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoTextField;
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/widgets/format.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Kind of [CatalogTextField], the catalog's `variant`.
enum TextFieldKind {
  /// One line.
  shortText,

  /// Several lines.
  longText,

  /// Digits.
  number,
}

/// The catalog `TextField`: the Signal underline field, kept in step with a
/// data-model value. A failed check shows its message once the member has
/// typed.
class CatalogTextField extends StatefulWidget {
  /// Creates a field.
  const new({
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.kind = TextFieldKind.shortText,
    this.error,
    super.key,
  });

  /// Caption above the field; also the spoken label.
  final String label;

  /// The bound value.
  final String value;

  /// Writes the value back; null makes the field read-only.
  final ValueChanged<String>? onChanged;

  /// Placeholder.
  final String? placeholder;

  /// Kind.
  final TextFieldKind kind;

  /// The first failed check's message.
  final String? error;

  @override
  State<CatalogTextField> createState() => _CatalogTextFieldState();
}

class _CatalogTextFieldState extends State<CatalogTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void didUpdateWidget(CatalogTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An agent update or another component changed the value.
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final hair = XpSpace.hairline(context);
    final error = _touched ? widget.error : null;
    final long = widget.kind == TextFieldKind.longText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text(
            widget.label,
            style: type.caption.copyWith(color: colors.inkSecondary),
          ),
        ),
        Semantics(
          label: widget.label,
          textField: true,
          child: CupertinoTextField.borderless(
            controller: _controller,
            focusNode: _focus,
            readOnly: widget.onChanged == null,
            onChanged: (text) {
              setState(() => _touched = true);
              widget.onChanged?.call(text);
            },
            keyboardType: switch (widget.kind) {
              TextFieldKind.number => const TextInputType.numberWithOptions(
                decimal: true,
              ),
              TextFieldKind.longText => TextInputType.multiline,
              TextFieldKind.shortText => TextInputType.text,
            },
            minLines: long ? 2 : 1,
            maxLines: long ? 6 : 1,
            placeholder: widget.placeholder,
            placeholderStyle: type.body.copyWith(color: colors.inkSecondary),
            style: type.body,
            cursorColor: colors.ink,
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: XpSpace.s12,
            ),
          ),
        ),
        SizedBox(
          height: _focus.hasFocus || error != null ? hair * 2 : hair,
          width: double.infinity,
          child: ColoredBox(
            color: error != null
                ? colors.danger
                : _focus.hasFocus
                ? colors.ink
                : colors.hairline,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: XpSpace.s4),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: type.meta.copyWith(color: colors.danger),
              ),
            ),
          ),
      ],
    );
  }
}

/// The catalog `DateTimeInput`: a row showing the value, opening the date
/// (and time) picker. Values are ISO 8601: `2026-11-22`, `13:20`, or
/// `2026-11-22T13:20:00`.
class CatalogDateTimeField extends StatelessWidget {
  /// Creates a field.
  const new({
    required this.value,
    required this.onChanged,
    this.label,
    this.enableDate = true,
    this.enableTime = false,
    this.min,
    this.max,
    super.key,
  });

  /// The bound value.
  final String value;

  /// Writes the value back; null makes the field read-only.
  final ValueChanged<String>? onChanged;

  /// Caption above the value.
  final String? label;

  /// Whether a date is picked.
  final bool enableDate;

  /// Whether a time is picked.
  final bool enableTime;

  /// Earliest allowed value.
  final String? min;

  /// Latest allowed value.
  final String? max;

  static final RegExp _time = RegExp(r'(\d{2}):(\d{2})');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final day = value.length >= 10 ? value.substring(0, 10) : null;
    final time = _time.firstMatch(
      value.length > 10 ? value.substring(10) : value,
    );
    final timeText = time == null ? null : '${time[1]}:${time[2]}';
    final shown = value.isEmpty
        ? l10n.a2uiDateTimeEmpty
        : enableDate && dayOf(day) != null
        ? dayLabel(context, day, time: enableTime ? timeText : null)
        : timeText ?? value;
    final title = label ?? l10n.a2uiDateTimeLabel;
    return XpDisclosure(
      title: title,
      value: shown,
      onTap: onChanged == null
          ? null
          : () => unawaited(_pick(context, day, timeText)),
    );
  }

  Future<void> _pick(BuildContext context, String? day, String? time) async {
    var date = dayOf(day) ?? today();
    if (enableDate || !enableTime) {
      final first = dayOf(min?.substring(0, 10)) ?? DateTime(2000);
      final last = dayOf(max?.substring(0, 10)) ?? DateTime(2100);
      final picked = await showDatePicker(
        context: context,
        initialDate: date.isBefore(first) || date.isAfter(last) ? first : date,
        firstDate: first,
        lastDate: last,
      );
      if (picked == null || !context.mounted) return;
      date = picked;
    }
    TimeOfDay? clockTime;
    if (enableTime) {
      final match = time == null ? null : _time.firstMatch(time);
      clockTime = await showTimePicker(
        context: context,
        initialTime: match == null
            ? TimeOfDay.now()
            : TimeOfDay(
                hour: int.parse(match[1]!),
                minute: int.parse(match[2]!),
              ),
      );
      if (clockTime == null || !context.mounted) return;
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final timeString = clockTime == null
        ? null
        : '${two(clockTime.hour)}:${two(clockTime.minute)}';
    onChanged!(switch ((enableDate, timeString)) {
      (true, final String t) => '${dayString(date)}T$t:00',
      (false, final String t) => t,
      (_, null) => dayString(date),
    });
  }
}
