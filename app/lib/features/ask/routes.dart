import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Routes of the Ask feature: the full-height screen pushed above the tabs
/// by the round glass button, and opened by `xpense://ask?text=…`.
///
/// WP-34 replaces the placeholder with the Ask thread (screen 7). Text from
/// a link is only prefilled; it is never sent until the user sends it.
FeatureRoutes askRoutes() => FeatureRoutes(
  routes: [
    GoRoute(
      path: AppRoutes.ask,
      pageBuilder: (context, state) => xpPage(
        context,
        state,
        _AskPlaceholder(
          prefill: state.uri.queryParameters[AppRoutes.textParam],
        ),
      ),
    ),
  ],
);

class _AskPlaceholder extends StatefulWidget {
  const new({this.prefill});

  final String? prefill;

  @override
  State<_AskPlaceholder> createState() => _AskPlaceholderState();
}

class _AskPlaceholderState extends State<_AskPlaceholder> {
  late final TextEditingController _text = TextEditingController(
    text: widget.prefill,
  );
  late CaptureMode _mode = (widget.prefill ?? '').isEmpty
      ? CaptureMode.voice
      : CaptureMode.type;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: XpColors.of(context).canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(
              title: l10n.askTitle,
              leading: const XpBackButton(),
              trailing: ModeChip(
                mode: PrivacyModeKind.smart,
                label: l10n.askModeSmart,
              ),
            ),
            // TODO(WP-31): the thread renders surfaces through
            // XpenseSurfaceHost from lib/a2ui/ (WP-31); WP-34 puts it here.
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: XpSpace.screenMargin,
                ),
                child: Center(child: EmptyState(message: l10n.askPlaceholder)),
              ),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: XpSpace.floatingMargin,
                end: XpSpace.floatingMargin,
                bottom: XpSpace.bottomControlOffset(context),
              ),
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
                onModeChanged: (mode) => setState(() => _mode = mode),
                // Talking, scanning and sending arrive with WP-34, WP-40
                // and WP-41; until then the buttons are disabled.
                onRecord: null,
                onScan: null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
