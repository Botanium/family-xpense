import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';

/// Routes of the Home feature: the first tab.
///
/// WP-23 replaces the placeholder with the Home screen (DESIGN_SYSTEM 9,
/// screen 6). Add Home's own screens here, never in the central router.
FeatureRoutes homeRoutes() => FeatureRoutes(
  branch: StatefulShellBranch(
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const _HomePlaceholder(),
      ),
    ],
  ),
);

class _HomePlaceholder extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PlaceholderScreen(
      title: l10n.homeTitle,
      message: l10n.homePlaceholder,
      trailing: GlassIconButton(
        glyph: XpGlyph.more,
        semanticLabel: l10n.homeSettingsButton,
        onPressed: () => context.push(AppRoutes.settings),
      ),
    );
  }
}
