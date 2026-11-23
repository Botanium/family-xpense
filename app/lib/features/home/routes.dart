import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/home/home_screen.dart';

/// Routes of the Home feature: the first tab (DESIGN_SYSTEM 9, screen 6).
///
/// Add Home's own screens here, never in the central router.
FeatureRoutes homeRoutes() => FeatureRoutes(
  branch: StatefulShellBranch(
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
      ),
    ],
  ),
);
