import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/activity/detail/entry_detail_screen.dart';

/// Routes of the Activity feature: the second tab and an entry's detail.
///
/// WP-22 replaces the tab placeholder (screen 16). The entry detail
/// (screen 17, WP-21) opens from `xpense://txn/{id}`.
FeatureRoutes activityRoutes() => FeatureRoutes(
  branch: StatefulShellBranch(
    routes: [
      GoRoute(
        path: AppRoutes.activity,
        builder: (context, state) => PlaceholderScreen(
          title: context.l10n.activityTitle,
          message: context.l10n.activityPlaceholder,
        ),
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
