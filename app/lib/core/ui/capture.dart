import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';

import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/glass/glass_surface.dart';
import 'package:xpense_app/core/ui/xp_icon.dart';
import 'package:xpense_app/core/ui/xp_pressable.dart';

/// Live level bars (DESIGN_SYSTEM 8.2). Driven by [levels] from the
/// recogniser; it animates only because the levels change, so it is still
/// whenever recording stops.
class Waveform extends StatelessWidget {
  /// Creates a waveform.
  const new({
    required this.levels,
    this.spoken,
    this.color,
    this.mini = false,
    super.key,
  });

  /// Bar heights from 0 to 1, oldest first.
  final List<double> levels;

  /// How many bars have been spoken; later bars are drawn quieter. Null
  /// draws every bar at full strength.
  final int? spoken;

  /// Bar colour; ink in the dock, orange in a transcript quote.
  final Color? color;

  /// Whether to draw the small transcript version (2 pt bars, 14 high).
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final barWidth = mini ? XpSpace.waveBarMini : XpSpace.waveBar;
    final height = mini ? XpSpace.waveHeightMini : XpSpace.waveHeight;
    final gap = mini ? XpSpace.s2 : XpSpace.waveBar;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep the newest bars that fit; never overflow the dock.
            final fit = constraints.maxWidth.isFinite
                ? ((constraints.maxWidth + gap) / (barWidth + gap)).floor()
                : levels.length;
            final skip = levels.length > fit ? levels.length - fit : 0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = skip; i < levels.length; i++) ...[
                  if (i > skip) SizedBox(width: gap),
                  SizedBox(
                    width: barWidth,
                    height: (levels[i].clamp(0.0, 1.0) * height).clamp(
                      barWidth,
                      height,
                    ),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: (color ?? colors.ink).withValues(
                          alpha: spoken != null && i >= spoken!
                              ? XpOpacity.waveQuiet
                              : 1,
                        ),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// What the user said, trailing-aligned, with a mini waveform and duration
/// when it was spoken (DESIGN_SYSTEM 8.2, Ask artboard).
class TranscriptQuote extends StatelessWidget {
  /// Creates a transcript quote.
  const new({required this.text, this.duration, this.levels, super.key});

  /// The words, without quotation marks.
  final String text;

  /// Clip length such as "0:06"; null for typed messages.
  final String? duration;

  /// Mini waveform levels; null for typed messages.
  final List<double>? levels;

  @override
  Widget build(BuildContext context) {
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: XpSpace.quoteMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (levels != null || duration != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: XpSpace.s6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (levels != null)
                      Waveform(
                        levels: levels!,
                        color: colors.accent,
                        mini: true,
                      ),
                    if (duration != null) ...[
                      const SizedBox(width: XpSpace.s6),
                      Text(
                        duration!,
                        style: type.monoLabel.copyWith(
                          color: colors.inkSecondary,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Text('“$text”', style: type.quote, textAlign: TextAlign.end),
          ],
        ),
      ),
    );
  }
}

/// Input mode of the [CaptureDock].
enum CaptureMode {
  /// Hold-to-talk with live waveform.
  voice,

  /// Text field.
  type,
}

/// Labels the dock speaks; supplied from the feature's ARB strings.
@immutable
class CaptureDockLabels {
  /// Creates the labels.
  const new({
    required this.typeInstead,
    required this.talk,
    required this.stop,
    required this.scan,
    required this.message,
    required this.hint,
  });

  /// "Type instead".
  final String typeInstead;

  /// "Talk".
  final String talk;

  /// "Stop listening".
  final String stop;

  /// "Scan a receipt".
  final String scan;

  /// "Message", the text field's label.
  final String message;

  /// Placeholder, such as "Spent, earned, lent…".
  final String hint;
}

/// The glass capture toolbar: voice, type and camera (DESIGN_SYSTEM 8.1).
///
/// The record button is solid orange with a halo ring, never glass on glass.
class CaptureDock extends StatelessWidget {
  /// Creates the dock.
  const new({
    required this.mode,
    required this.labels,
    required this.onModeChanged,
    required this.onRecord,
    required this.onScan,
    this.recording = false,
    this.levels = const [],
    this.spoken,
    this.controller,
    this.onSubmitted,
    super.key,
  });

  /// Voice or type.
  final CaptureMode mode;

  /// Spoken and visible labels.
  final CaptureDockLabels labels;

  /// Switches mode.
  final ValueChanged<CaptureMode> onModeChanged;

  /// Starts or stops recording.
  final VoidCallback? onRecord;

  /// Opens the camera.
  final VoidCallback? onScan;

  /// Whether the microphone is live.
  final bool recording;

  /// Live waveform levels.
  final List<double> levels;

  /// How many bars have been spoken.
  final int? spoken;

  /// Text field controller in type mode.
  final TextEditingController? controller;

  /// Sends typed text.
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final motion = XpMotion.of(context);
    return GlassSurface(
      variant: GlassVariant.dock,
      shape: const RoundedSuperellipseBorder(borderRadius: XpRadius.dockAll),
      padding: const EdgeInsetsDirectional.all(XpSpace.dockPadding),
      child: AnimatedSwitcher(
        duration: motion.slow,
        switchInCurve: XpMotion.slowCurve,
        child: mode == CaptureMode.voice
            ? _VoiceRow(key: const ValueKey(CaptureMode.voice), dock: this)
            : _TypeRow(key: const ValueKey(CaptureMode.type), dock: this),
      ),
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const new({required this.dock, super.key});

  final CaptureDock dock;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return Row(
      children: [
        _WellButton(
          glyph: XpGlyph.keyboard,
          label: dock.labels.typeInstead,
          onPressed: () => dock.onModeChanged(CaptureMode.type),
        ),
        const SizedBox(width: XpSpace.s12),
        Expanded(
          child: dock.levels.isEmpty
              ? const SizedBox(height: XpSpace.waveHeight)
              : Waveform(levels: dock.levels, spoken: dock.spoken),
        ),
        const SizedBox(width: XpSpace.s12),
        _WellButton(
          glyph: XpGlyph.camera,
          label: dock.labels.scan,
          onPressed: dock.onScan,
        ),
        const SizedBox(width: XpSpace.s12),
        _RecordButton(
          recording: dock.recording,
          label: dock.recording ? dock.labels.stop : dock.labels.talk,
          onPressed: dock.onRecord,
          halo: colors.accentHalo,
        ),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const new({required this.dock, super.key});

  final CaptureDock dock;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    final type = XpType.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: dock.labels.message,
            textField: true,
            child: CupertinoTextField.borderless(
              controller: dock.controller,
              placeholder: dock.labels.hint,
              placeholderStyle: type.body.copyWith(color: colors.inkSecondary),
              style: type.body,
              cursorColor: colors.ink,
              textInputAction: TextInputAction.send,
              onSubmitted: dock.onSubmitted,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: XpSpace.s16,
                vertical: XpSpace.s12,
              ),
              decoration: BoxDecoration(
                color: colors.controlWell,
                borderRadius: const BorderRadiusDirectional.all(
                  Radius.circular(XpRadius.well),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: XpSpace.s8),
        _WellButton(
          glyph: XpGlyph.camera,
          label: dock.labels.scan,
          onPressed: dock.onScan,
        ),
        const SizedBox(width: XpSpace.s8),
        _RecordButton(
          recording: false,
          small: true,
          label: dock.labels.talk,
          onPressed: () => dock.onModeChanged(CaptureMode.voice),
          halo: null,
        ),
      ],
    );
  }
}

class _WellButton extends StatelessWidget {
  const new({
    required this.glyph,
    required this.label,
    required this.onPressed,
  });

  final XpGlyph glyph;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => XpPressable(
    onPressed: onPressed,
    semanticLabel: label,
    excludeChildSemantics: true,
    child: SizedBox.square(
      dimension: XpSpace.dockSideButton,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: XpColors.of(context).controlWell,
          shape: const CircleBorder(),
        ),
        child: Center(child: XpIcon(glyph, size: XpSpace.iconTop)),
      ),
    ),
  );
}

class _RecordButton extends StatelessWidget {
  const new({
    required this.recording,
    required this.label,
    required this.onPressed,
    required this.halo,
    this.small = false,
  });

  final bool recording;
  final String label;
  final VoidCallback? onPressed;
  final Color? halo;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return XpPressable(
      onPressed: onPressed == null
          ? null
          : () {
              unawaited(XpHaptics.micToggle());
              onPressed!();
            },
      semanticLabel: label,
      excludeChildSemantics: true,
      child: SizedBox.square(
        dimension: small ? XpSpace.dockSideButton : XpSpace.dockRecordButton,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
            boxShadow: halo == null || !recording
                ? null
                : [BoxShadow(color: halo!, spreadRadius: XpSpace.recordHalo)],
          ),
          child: Center(
            child: XpIcon(
              recording ? XpGlyph.stop : XpGlyph.mic,
              size: XpSpace.iconTop,
              color: colors.inkOnAccent,
            ),
          ),
        ),
      ),
    );
  }
}
