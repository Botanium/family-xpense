import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';

/// Routes of the Accounts feature: the fourth tab.
///
/// WP-13 replaces the placeholder with Accounts and adds account detail
/// (screens 10 and 11).
FeatureRoutes accountsRoutes() => FeatureRoutes(
  branch: StatefulShellBranch(
    routes: [
      GoRoute(
        path: AppRoutes.accounts,
        builder: (context, state) => PlaceholderScreen(
          title: context.l10n.accountsTitle,
          message: context.l10n.accountsPlaceholder,
        ),
      ),
    ],
  ),
);
