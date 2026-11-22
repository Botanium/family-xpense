import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xpense_app/a2ui/xpense_surface_host.dart';
import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/features/ask/ask_actions.dart';
import 'package:xpense_app/features/ask/ask_controller.dart';
import 'package:xpense_app/features/ask/ask_state.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Screen 7, Ask (DESIGN_SYSTEM 9): glass back, "ASK", the mode chip; the
/// thread of quotes and surfaces; the capture dock in type mode.
///
/// Text from a link is only prefilled; it is never sent until the member
/// sends it.
class AskScreen extends ConsumerStatefulWidget {
  /// Creates the screen, with [prefill] in the text field.
  const new({this.prefill, super.key});

  /// Text from `xpense://ask?text=…`.
  final String? prefill;

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  late final TextEditingController _text = TextEditingController(
    text: widget.prefill,
  );
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  // Voice arrives with WP-40; Ask opens ready to type.
  CaptureMode _mode = CaptureMode.type;

  // A second `xpense://ask?text=…` link while Ask is on screen reuses this
  // page with a new prefill: show the new text. A rebuild with the same
  // prefill, or a link without text, keeps what the member typed.
  @override
  void didUpdateWidget(AskScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prefill = widget.prefill;
    if (prefill == null || prefill.isEmpty || prefill == oldWidget.prefill) {
      return;
    }
    _text.value = TextEditingValue(
      text: prefill,
      selection: TextSelection.collapsed(offset: prefill.length),
    );
    _mode = CaptureMode.type;
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(String text) {
    // While a request runs the text stays in the field, unsent.
    if (text.trim().isEmpty || ref.read(askControllerProvider).busy) return;
    _text.clear();
    unawaited(ref.read(askControllerProvider.notifier).send(text));
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final motion = XpMotion.of(context);
      final end = _scroll.position.maxScrollExtent;
      if (motion.isReduced) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(
          end,
          duration: motion.base,
          curve: XpMotion.baseCurve,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = XpColors.of(context);
    final state = ref.watch(askControllerProvider);
    final controller = ref.read(askControllerProvider.notifier);
    ref.listen(
      askControllerProvider.select((s) => (s.items.length, s.busy)),
      (_, _) => _scrollToEnd(),
    );
    final bottom = XpSpace.bottomControlOffset(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(
              title: l10n.askTitle,
              leading: const XpBackButton(),
              trailing: ListenableBuilder(
                listenable: _text,
                builder: (context, _) => _AskModeChip(
                  mode: ref.watch(capturePrivacyModeProvider),
                  preview: controller.preview(_text.text),
                ),
              ),
            ),
            if (state.offline) ...[
              const SizedBox(height: XpSpace.s8),
              OfflineBanner(message: l10n.askOffline),
            ],
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _Thread(
                      state: state,
                      host: controller.host,
                      scroll: _scroll,
                      bottomInset:
                          bottom +
                          XpSpace.dockRecordButton +
                          2 * XpSpace.dockPadding +
                          XpSpace.s24,
                    ),
                  ),
                  PositionedDirectional(
                    start: XpSpace.floatingMargin,
                    end: XpSpace.floatingMargin,
                    bottom: bottom,
                    child: CaptureDock(
                      mode: _mode,
                      labels: CaptureDockLabels(
                        typeInstead: l10n.askDockTypeInstead,
                        talk: l10n.askDockTalk,
                        stop: l10n.askDockStop,
                        scan: l10n.askDockScan,
                        message: l10n.askDockMessage,
                        hint: l10n.askDockHint,
                      ),
                      controller: _text,
                      onSubmitted: _send,
                      onModeChanged: (mode) => setState(() => _mode = mode),
                      // Talking and scanning arrive with WP-40 and WP-41.
                      onRecord: null,
                      onScan: null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The mode chip: what the message being typed will do (ARCHITECTURE 6).
/// With nothing typed it names the household's mode.
class _AskModeChip extends StatelessWidget {
  const new({required this.mode, required this.preview});

  final CapturePrivacyMode mode;
  final RouteDecision? preview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (kind, label) = switch ((mode, preview?.path)) {
      (CapturePrivacyMode.onDevice, _) || (_, CapturePath.local) => (
        PrivacyModeKind.onDevice,
        l10n.askModeOnDevice,
      ),
      (_, CapturePath.decide) => (PrivacyModeKind.smart, l10n.askModeDecide),
      (_, CapturePath.agent) || (CapturePrivacyMode.cloud, null) => (
        PrivacyModeKind.cloud,
        l10n.askModeCloud,
      ),
      (CapturePrivacyMode.smart, null) => (
        PrivacyModeKind.smart,
        l10n.askModeSmart,
      ),
    };
    return ModeChip(mode: kind, label: label);
  }
}

class _Thread extends StatelessWidget {
  const new({
    required this.state,
    required this.host,
    required this.scroll,
    required this.bottomInset,
  });

  final AskState state;
  final XpenseSurfaceHost host;
  final ScrollController scroll;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (state.items.isEmpty && !state.busy) {
      return Padding(
        padding: EdgeInsetsDirectional.only(
          start: XpSpace.screenMargin,
          end: XpSpace.screenMargin,
          bottom: bottomInset,
        ),
        child: Center(child: EmptyState(message: l10n.askEmpty)),
      );
    }
    final rows = [
      for (final item in state.items) _row(context, item),
      if (state.busy) const _BusyRow(key: ValueKey('busy')),
    ];
    return ListView.separated(
      controller: scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsetsDirectional.only(
        start: XpSpace.screenMargin,
        end: XpSpace.screenMargin,
        top: XpSpace.s24,
        bottom: bottomInset,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: XpSpace.s24),
      itemBuilder: (_, i) => rows[i],
    );
  }

  Widget _row(BuildContext context, ThreadItem item) => switch (item) {
    QuoteItem(:final key, :final text) => TranscriptQuote(
      key: ValueKey(key),
      text: text,
    ),
    ReplyItem(:final key, :final text) => _Reply(
      key: ValueKey(key),
      text: text,
    ),
    SurfaceItem(:final surfaceId) => SurfaceView(
      key: ValueKey(surfaceId),
      host: host,
      surfaceId: surfaceId,
    ),
    final NoticeItem notice => _Notice(key: ValueKey(notice.key), item: notice),
  };
}

class _Reply extends StatelessWidget {
  const new({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(text.trim(), style: XpType.of(context).body),
  );
}

class _BusyRow extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    return Row(
      children: [
        XpSpinner(semanticLabel: l10n.askThinking),
        const SizedBox(width: XpSpace.s12),
        Expanded(
          child: ExcludeSemantics(
            child: Text(
              l10n.askThinking,
              style: type.caption.copyWith(color: colors.inkSecondary),
            ),
          ),
        ),
        XpButton.text(
          label: l10n.askStop,
          onPressed: () =>
              unawaited(ref.read(askControllerProvider.notifier).cancel()),
        ),
      ],
    );
  }
}

class _Notice extends ConsumerWidget {
  const new({required this.item, super.key});

  final NoticeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final type = XpType.of(context);
    final colors = XpColors.of(context);
    final controller = ref.read(askControllerProvider.notifier);
    final busy = ref.watch(askControllerProvider.select((s) => s.busy));
    final message = switch (item.kind) {
      AskNoticeKind.offline => l10n.askNoticeOffline,
      AskNoticeKind.limit => l10n.askNoticeLimit,
      AskNoticeKind.privacy => l10n.askNoticePrivacy,
      AskNoticeKind.error => l10n.askNoticeError,
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              XpIcon(
                item.kind == AskNoticeKind.offline
                    ? XpGlyph.offline
                    : item.kind == AskNoticeKind.privacy
                    ? XpGlyph.lock
                    : XpGlyph.sparkle,
                size: XpSpace.iconRow,
                color: colors.inkSecondary,
              ),
              const SizedBox(width: XpSpace.s8),
              Expanded(child: Text(message, style: type.body)),
            ],
          ),
          if (item.canRetry || item.canFinishManually)
            Wrap(
              spacing: XpSpace.s16,
              children: [
                if (item.canRetry)
                  XpButton.text(
                    label: l10n.askRetry,
                    onPressed: busy
                        ? null
                        : () => unawaited(controller.retry(item.text)),
                  ),
                if (item.canFinishManually)
                  XpButton.text(
                    label: l10n.askFinishManually,
                    onPressed: busy
                        ? null
                        : () => controller.finishManually(item.text),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
