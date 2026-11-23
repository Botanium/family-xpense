import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/activity/activity_screen.dart';
import 'package:xpense_app/features/activity/detail/entry_detail_screen.dart';

/// Routes of the Activity feature: the second tab and an entry's detail.
///
/// WP-22 built the tab (screen 16); WP-21 the entry detail (screen 17),
/// which `xpense://txn/{id}` opens.
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
        EntryDetailScreen(txnId: state.pathParameters[AppRoutes.idParam] ?? ''),
      ),
    ),
  ],
);
