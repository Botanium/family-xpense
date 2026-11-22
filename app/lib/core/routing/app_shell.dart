import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/app_routes.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// The four tabs, in tab bar order (FABLE_PROMPT 3, DESIGN_SYSTEM 8.1).
enum AppTab {
  /// Home.
  home(XpGlyph.home),

  /// Activity.
  activity(XpGlyph.activity),

  /// Goals.
  goals(XpGlyph.goals),

  /// Accounts.
  accounts(XpGlyph.accounts);

  new(this.glyph);

  /// The tab's icon.
  final XpGlyph glyph;

  /// The tab's label.
  String label(AppLocalizations l10n) => switch (this) {
    AppTab.home => l10n.shellTabHome,
    AppTab.activity => l10n.shellTabActivity,
    AppTab.goals => l10n.shellTabGoals,
    AppTab.accounts => l10n.shellTabAccounts,
  };
}

/// The tab screens with the floating glass tab bar and the round Ask
/// button over them (DESIGN_SYSTEM 8.1).
///
/// Each tab keeps its own navigation stack and scroll position
/// (`StatefulShellRoute.indexedStack`). Tapping the current tab returns it
/// to its root. The Ask button pushes Ask above the shell.
class AppShell extends StatelessWidget {
  /// Creates the shell around [navigationShell].
  const new({required this.navigationShell, super.key});

  /// The tab branches, from go_router.
  final StatefulNavigationShell navigationShell;

  void _select(int index) => navigationShell.goBranch(
    index,
    initialLocation: index == navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const margin = XpSpace.floatingMargin;
    return Scaffold(
      backgroundColor: XpColors.of(context).canvas,
      body: Stack(
        children: [
          // Content first, so VoiceOver reads it before the tab bar
          // (DESIGN_SYSTEM 11, focus order).
          Positioned.fill(child: navigationShell),
          PositionedDirectional(
            start: margin,
            end: margin,
            bottom: XpSpace.bottomControlOffset(context),
            child: XpTabBarWithAsk(
              tabBar: XpTabBar(
                items: [
                  for (final tab in AppTab.values)
                    XpTabItem(glyph: tab.glyph, label: tab.label(l10n)),
                ],
                selectedIndex: navigationShell.currentIndex,
                onSelected: _select,
              ),
              askButton: AskButton(
                semanticLabel: l10n.shellAskButton,
                onPressed: () => context.push(AppRoutes.ask),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
