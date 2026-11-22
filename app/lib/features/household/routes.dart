import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/household/household_setup_screen.dart';
import 'package:xpense_app/features/household/join_screen.dart';

/// Routes of the Household feature: household setup (screen 3) and joining
/// from an invite, which `xpense://join?code=…` opens with the code in the
/// query (WP-12).
///
/// Who may open them is decided by the onboarding gate: a signed-in person
/// without a household may open only these two.
FeatureRoutes householdRoutes() => FeatureRoutes(
  routes: [
    GoRoute(
      path: AppRoutes.householdSetup,
      pageBuilder: (context, state) =>
          xpPage(context, state, const HouseholdSetupScreen()),
    ),
    GoRoute(
      path: AppRoutes.join,
      pageBuilder: (context, state) {
        final code = state.uri.queryParameters[AppRoutes.codeParam];
        // A new link while the screen shows starts it again with that code.
        return xpPage(
          context,
          state,
          JoinScreen(key: ValueKey(code), initialCode: code),
        );
      },
    ),
  ],
);
