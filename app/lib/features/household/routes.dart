import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';

/// Routes of the Household feature: joining from an invite, which
/// `xpense://join?code=…` opens with the code in the query.
///
/// WP-12 replaces the placeholder and adds household setup (screen 3).
FeatureRoutes householdRoutes() => FeatureRoutes(
  routes: [
    GoRoute(
      path: AppRoutes.join,
      pageBuilder: (context, state) => xpPage(
        context,
        state,
        PlaceholderScreen(
          title: context.l10n.householdJoinTitle,
          message: context.l10n.householdJoinPlaceholder,
          pushed: true,
        ),
      ),
    ),
  ],
);
