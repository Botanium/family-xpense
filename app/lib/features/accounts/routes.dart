import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/accounts/account_detail_screen.dart';
import 'package:xpense_app/features/accounts/accounts_screen.dart';
import 'package:xpense_app/features/accounts/add_accounts_screen.dart';

/// Routes of the Accounts feature (WP-13): the fourth tab (screen 10), an
/// account's detail pushed above the shell (screen 11), and Add accounts,
/// onboarding step 3 (screen 4).
FeatureRoutes accountsRoutes() => FeatureRoutes(
  branch: StatefulShellBranch(
    routes: [
      GoRoute(
        path: AppRoutes.accounts,
        builder: (context, state) => const AccountsScreen(),
      ),
    ],
  ),
  routes: [
    GoRoute(
      path: AppRoutes.accountPattern,
      pageBuilder: (context, state) => xpPage(
        context,
        state,
        AccountDetailScreen(
          accountId: state.pathParameters[AppRoutes.idParam] ?? '',
        ),
      ),
    ),
    GoRoute(
      path: AppRoutes.addAccounts,
      pageBuilder: (context, state) =>
          xpPage(context, state, const AddAccountsScreen()),
    ),
  ],
);
