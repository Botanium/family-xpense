import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/app_routes.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// A screen that holds a place in the navigation until its package builds
/// it: the Signal top bar and one line saying what will appear here.
///
/// Used by the `routes.dart` stubs; each feature replaces its placeholder
/// with the real screen in its own package.
class PlaceholderScreen extends StatelessWidget {
  /// Creates a placeholder.
  const new({
    required this.title,
    required this.message,
    this.trailing,
    this.pushed = false,
    super.key,
  });

  /// Top bar title; upper-cased by the bar.
  final String title;

  /// One line saying what will appear here.
  final String message;

  /// Trailing top bar control, such as a glass button.
  final Widget? trailing;

  /// Whether the screen is pushed above the shell, which adds the glass back
  /// button and drops the room kept for the tab bar.
  final bool pushed;

  @override
  Widget build(BuildContext context) {
    final colors = XpColors.of(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            XpTopBar(
              title: title,
              leading: pushed ? const XpBackButton() : null,
              trailing: trailing,
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: XpSpace.screenMargin,
                  end: XpSpace.screenMargin,
                  bottom: pushed
                      ? XpSpace.bottomControlOffset(context)
                      : XpSpace.contentBottomPadding(context),
                ),
                child: Center(child: EmptyState(message: message)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round glass back button of a pushed screen.
///
/// Pops when there is a screen below; after a cold start from a deep link
/// there is none, so it goes to Home instead.
class XpBackButton extends StatelessWidget {
  /// Creates the back button.
  const new({super.key});

  @override
  Widget build(BuildContext context) => GlassIconButton(
    glyph: XpGlyph.back,
    semanticLabel: context.l10n.shellBack,
    onPressed: () =>
        context.canPop() ? context.pop() : context.go(AppRoutes.home),
  );
}
