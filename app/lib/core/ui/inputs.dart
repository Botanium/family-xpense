import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/xp_icon.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// Search field: a sunken stadium well (DESIGN_SYSTEM 8.1). In Activity it
/// doubles as "Search or ask".
class XpSearchField extends StatelessWidget {
  /// Creates a search field.
  const new({
    required this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  /// Placeholder and spoken label.
  final String hint;

  /// Text controller.
  final TextEditingController? controller;

  /// Called on every edit.
  final ValueChanged<String>? onChanged;

  /// Called on the keyboard's search key.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return Semantics(
      label: hint,
      textField: true,
      child: CupertinoTextField.borderless(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        placeholder: hint,
        placeholderStyle: type.body.copyWith(color: colors.inkSecondary),
        style: type.body,
        cursorColor: colors.ink,
        textInputAction: TextInputAction.search,
        prefix: Padding(
          padding: const EdgeInsetsDirectional.only(start: XpSpace.s16),
          child: XpIcon(
            XpGlyph.search,
            size: XpSpace.iconRow,
            color: colors.inkSecondary,
          ),
        ),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: XpSpace.s8,
          vertical: XpSpace.s12,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: const BorderRadiusDirectional.all(
            Radius.circular(XpRadius.well),
          ),
        ),
      ),
    );
  }
}

/// Underline text field with a caption label above (DESIGN_SYSTEM 8.1).
class XpTextField extends StatefulWidget {
  /// Creates a text field.
  const new({
    required this.label,
    this.controller,
    this.hint,
    this.error,
    this.onChanged,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
    super.key,
  });

  /// Caption above the field; also the spoken label.
  final String label;

  /// Text controller.
  final TextEditingController? controller;

  /// Placeholder.
  final String? hint;

  /// Inline error under the field, in `danger`.
  final String? error;

  /// Called on every edit.
  final ValueChanged<String>? onChanged;

  /// Keyboard.
  final TextInputType? keyboardType;

  /// Whether to hide the text, for passwords.
  final bool obscureText;

  /// What iOS may autofill, such as `AutofillHints.email`.
  final Iterable<String>? autofillHints;

  /// The keyboard's return key.
  final TextInputAction? textInputAction;

  /// Called when the return key is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field accepts input.
  final bool enabled;

  @override
  State<XpTextField> createState() => _XpTextFieldState();
}

class _XpTextFieldState extends State<XpTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final hair = XpSpace.hairline(context);
    final underline = widget.error != null
        ? colors.danger
        : _focus.hasFocus
        ? colors.ink
        : colors.hairline;
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
            controller: widget.controller,
            focusNode: _focus,
            onChanged: widget.onChanged,
            keyboardType: widget.keyboardType,
            obscureText: widget.obscureText,
            autocorrect: !widget.obscureText,
            enableSuggestions: !widget.obscureText,
            autofillHints: widget.autofillHints,
            textInputAction: widget.textInputAction,
            onSubmitted: widget.onSubmitted,
            enabled: widget.enabled,
            placeholder: widget.hint,
            placeholderStyle: type.body.copyWith(color: colors.inkSecondary),
            style: type.body,
            cursorColor: colors.ink,
            padding: const EdgeInsetsDirectional.symmetric(
              vertical: XpSpace.s12,
            ),
          ),
        ),
        SizedBox(
          height: _focus.hasFocus || widget.error != null ? hair * 2 : hair,
          width: double.infinity,
          child: ColoredBox(color: underline),
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: XpSpace.s4),
            child: Text(
              widget.error!,
              style: type.meta.copyWith(color: colors.danger),
            ),
          ),
      ],
    );
  }
}

/// Large mono amount entry with a currency toggle (DESIGN_SYSTEM 8.1).
///
/// Accepts digits and, when the currency has decimals, one point with at
/// most [exponent] digits after it. Turn the text into minor units with
/// `MoneyFormat.parseMinor`.
class AmountField extends StatelessWidget {
  /// Creates an amount field.
  const new({
    required this.label,
    required this.currency,
    required this.exponent,
    this.controller,
    this.onChanged,
    this.onCurrencyPressed,
    this.currencyLabel,
    super.key,
  });

  /// Spoken label, such as "Amount".
  final String label;

  /// Currency code shown on the toggle.
  final String currency;

  /// Decimal places allowed.
  final int exponent;

  /// Text controller.
  final TextEditingController? controller;

  /// Called on every edit with the raw text.
  final ValueChanged<String>? onChanged;

  /// Switches currency; null hides the toggle affordance.
  final VoidCallback? onCurrencyPressed;

  /// Spoken label of the currency toggle, such as "Currency, IQD. Change".
  final String? currencyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    final pattern = exponent == 0
        ? RegExp(r'^\d*$')
        : RegExp('^\\d*(\\.\\d{0,$exponent})?\$');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            XpPressable(
              onPressed: onCurrencyPressed,
              semanticLabel: currencyLabel ?? currency,
              excludeChildSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(currency, style: type.figureMarkHero),
                  if (onCurrencyPressed != null)
                    XpIcon(
                      XpGlyph.chevronDown,
                      size: XpSpace.iconPill,
                      color: colors.inkSecondary,
                    ),
                ],
              ),
            ),
            const SizedBox(width: XpSpace.s8),
            Expanded(
              child: Semantics(
                label: label,
                textField: true,
                child: CupertinoTextField.borderless(
                  controller: controller,
                  onChanged: onChanged,
                  placeholder: '0',
                  placeholderStyle: type.figureLarge.copyWith(
                    color: colors.inkTertiary,
                  ),
                  style: type.figureLarge,
                  cursorColor: colors.ink,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: exponent > 0,
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction(
                      (old, next) => pattern.hasMatch(next.text) ? next : old,
                    ),
                  ],
                  padding: const EdgeInsetsDirectional.symmetric(
                    vertical: XpSpace.s8,
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(
          height: XpSpace.hairline(context),
          child: ColoredBox(color: colors.hairline),
        ),
      ],
    );
  }
}

/// A 3 × 4 number pad for the rate sheet: digits, point, backspace.
class XpNumberPad extends StatelessWidget {
  /// Creates a number pad.
  const new({
    required this.onKey,
    required this.backspaceLabel,
    this.allowPoint = true,
    super.key,
  });

  /// Called with `0`–`9`, `.` or [backspace].
  final ValueChanged<String> onKey;

  /// Spoken label for the backspace key.
  final String backspaceLabel;

  /// Whether the point key is enabled.
  final bool allowPoint;

  /// Key value reported for backspace.
  static const String backspace = '⌫';

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', backspace],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in keys)
          Row(
            children: [
              for (final key in row)
                Expanded(
                  child: XpPressable(
                    onPressed: key == '.' && !allowPoint
                        ? null
                        : () {
                            unawaited(XpHaptics.picked());
                            onKey(key);
                          },
                    semanticLabel: key == backspace ? backspaceLabel : key,
                    excludeChildSemantics: true,
                    minSize: const Size(
                      XpSpace.minTarget,
                      XpSpace.buttonHeight,
                    ),
                    child: Text(key, style: type.figureMedium),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
