import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';

/// Routes of the Loans feature: a loan or debt's detail, which
/// `xpense://loan/{id}` opens.
///
/// WP-50 replaces the placeholder (screen 15) and adds Loans and debts
/// (screen 14).
FeatureRoutes loansRoutes() => FeatureRoutes(
  routes: [
    GoRoute(
      path: AppRoutes.loanPattern,
      pageBuilder: (context, state) => xpPage(
        context,
        state,
        PlaceholderScreen(
          title: context.l10n.loansTitle,
          message: context.l10n.loansPlaceholder,
          pushed: true,
        ),
      ),
    ),
  ],
);
