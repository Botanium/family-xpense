import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';

/// Routes of the Goals feature: the third tab.
///
/// WP-51 replaces the placeholder with Goals and adds goal detail
/// (screens 12 and 13).
FeatureRoutes goalsRoutes() => FeatureRoutes(
  branch: StatefulShellBranch(
    routes: [
      GoRoute(
        path: AppRoutes.goals,
        builder: (context, state) => PlaceholderScreen(
          title: context.l10n.goalsTitle,
          message: context.l10n.goalsPlaceholder,
        ),
      ),
    ],
  ),
);
