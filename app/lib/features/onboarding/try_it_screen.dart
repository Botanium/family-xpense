import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/onboarding/onboarding_layout.dart';
import 'package:xpense_app/features/onboarding/try_it_view_model.dart';

/// Width of the mono tag column of the example rows (artboard 05).
const double _tagWidth = XpSpace.s40 * 2 + XpSpace.s8;

/// Try it (DESIGN_SYSTEM 9, screen 5; PRD ON-6): the first capture before
/// Home.
///
/// The microphone pre-prompt sits on the screen itself, above the
/// examples, so the person knows what the orange button turns on before
/// iOS asks (DESIGN_SYSTEM 12, item 7). "Type instead" is always visible.
/// What the person says or types goes to [TryItCapture], a stub until
/// capture exists.
class TryItScreen extends ConsumerStatefulWidget {
  /// Creates Try it.
  const new({super.key});

  @override
  ConsumerState<TryItScreen> createState() => _TryItScreenState();
}

class _TryItScreenState extends ConsumerState<TryItScreen> {
  final TextEditingController _text = TextEditingController();

  TryItViewModel get _viewModel => ref.read(tryItViewModelProvider.notifier);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send(String text) {
    unawaited(_viewModel.submit(text));
    _text.clear();
  }

  void _useExample(String example) {
    _viewModel.setMode(CaptureMode.type);
    _text.text = example;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(tryItViewModelProvider);
    final sent = state.sent;
    final notice = switch (state.notice) {
      null => null,
      VoiceNotice.unavailable => l10n.onboardingTryItVoiceUnavailable,
      VoiceNotice.denied => l10n.onboardingTryItMicDenied,
      VoiceNotice.failed => l10n.onboardingTryItVoiceFailed,
    };
    final offset = XpSpace.bottomControlOffset(context);
    return Scaffold(
      backgroundColor: XpColors.of(context).canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: XpSpace.s8),
            XpTopBar(
              title: l10n.onboardingTryItTitle,
              // Right after signing in there is nothing to go back to.
              leading: context.canPop() ? const XpBackButton() : null,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.only(
                  start: XpSpace.screenMargin,
                  end: XpSpace.screenMargin,
                  top: XpSpace.s16,
                  bottom: XpSpace.s16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StepBar(
                      current: onboardingStepCount,
                      semanticLabel: l10n.onboardingStep(
                        onboardingStepCount,
                        onboardingStepCount,
                      ),
                    ),
                    const SizedBox(height: XpSpace.s24),
                    OnboardingHeading(l10n.onboardingTryItHeadline),
                    const SizedBox(height: XpSpace.s8),
                    OnboardingParagraph(l10n.onboardingTryItBody),
                    if (sent == null) ...[
                      const SizedBox(height: XpSpace.s16),
                      const _MicNote(),
                      const SizedBox(height: XpSpace.s24),
                      _Examples(onPick: _useExample),
                    ] else ...[
                      const SizedBox(height: XpSpace.s32),
                      TranscriptQuote(text: sent),
                      const SizedBox(height: XpSpace.s16),
                      OnboardingMessage.note(l10n.onboardingTryItReply),
                      const SizedBox(height: XpSpace.s24),
                      XpButton.primary(
                        label: l10n.onboardingTryItDone,
                        onPressed: () => context.go(AppRoutes.home),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (notice != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: XpSpace.screenMargin,
                  end: XpSpace.screenMargin,
                  bottom: XpSpace.s8,
                ),
                child: OnboardingMessage.note(notice),
              ),
            if (sent == null)
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: XpSpace.screenMargin,
                ),
                // Wraps onto two lines at large text sizes.
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    XpButton.text(
                      label: l10n.onboardingTryItTypeInstead,
                      onPressed: () => _viewModel.setMode(CaptureMode.type),
                    ),
                    XpButton.text(
                      label: l10n.onboardingTryItSkip,
                      onPressed: () => context.go(AppRoutes.home),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: XpSpace.s8),
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: XpSpace.floatingMargin,
                end: XpSpace.floatingMargin,
                bottom: offset,
              ),
              child: CaptureDock(
                mode: state.mode,
                labels: CaptureDockLabels(
                  typeInstead: l10n.onboardingTryItTypeInstead,
                  talk: l10n.onboardingTryItTalk,
                  stop: l10n.onboardingTryItStop,
                  scan: l10n.onboardingTryItScan,
                  message: l10n.onboardingTryItMessage,
                  hint: l10n.onboardingTryItHint,
                ),
                onModeChanged: _viewModel.setMode,
                onRecord: state.sending
                    ? null
                    : () => unawaited(_viewModel.toggleListening()),
                // Receipts are not part of the first try (WP-41).
                onScan: null,
                recording: state.listening,
                levels: state.levels,
                controller: _text,
                onSubmitted: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The microphone pre-prompt (DESIGN_SYSTEM 12, item 7).
class _MicNote extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        XpIcon(XpGlyph.mic, size: XpSpace.iconRow, color: colors.inkSecondary),
        const SizedBox(width: XpSpace.s8),
        Expanded(
          child: Text(
            context.l10n.onboardingTryItMicNote,
            style: XpType.of(context).caption
                .copyWith(color: colors.inkSecondary),
          ),
        ),
      ],
    );
  }
}

/// "Things you can say": four examples with mono tags. Tapping one puts it
/// in the text field, ready to send.
class _Examples extends StatelessWidget {
  const new({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final examples = [
      (l10n.onboardingTryItTagExpense, l10n.onboardingTryItExampleExpense),
      (l10n.onboardingTryItTagTwo, l10n.onboardingTryItExampleTwo),
      (l10n.onboardingTryItTagLoan, l10n.onboardingTryItExampleLoan),
      (l10n.onboardingTryItTagQuestion, l10n.onboardingTryItExampleQuestion),
    ];
    final colors = XpColors.of(context);
    final tagStyle = XpType.of(context).monoLabel
        .copyWith(color: colors.inkSecondary);
    return XpSection(
      label: l10n.onboardingTryItExamples,
      children: [
        for (final (tag, example) in examples)
          XpListRow(
            leading: SizedBox(
              width: _tagWidth,
              child: Text(tag.toUpperCase(), style: tagStyle),
            ),
            title: '“$example”',
            onTap: () => onPick(example),
          ),
      ],
    );
  }
}
