import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/activity/activity_screen.dart';

/// Routes of the Activity feature: the second tab and an entry's detail.
///
/// WP-22 built the tab (screen 16); WP-21 replaces the entry
/// detail (screen 17), which `xpense://txn/{id}` opens.
FeatureRoutes activityRoutes() => FeatureRoutes(
  branch: StatefulShellBranch(
    routes: [
      GoRoute(
        path: AppRoutes.activity,
        builder: (context, state) => const ActivityScreen(),
      ),
    ],
  ),
  routes: [
    GoRoute(
      path: AppRoutes.entryPattern,
      pageBuilder: (context, state) => xpPage(
        context,
        state,
        PlaceholderScreen(
          title: context.l10n.activityEntryTitle,
          message: context.l10n.activityEntryPlaceholder,
          pushed: true,
        ),
      ),
    ),
  ],
);
