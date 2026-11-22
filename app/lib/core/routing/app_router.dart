import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/routing/app_routes.dart';
import 'package:xpense_app/core/routing/app_shell.dart';
import 'package:xpense_app/core/routing/deep_link.dart';
import 'package:xpense_app/core/routing/not_found_screen.dart';
import 'package:xpense_app/core/routing/route_page.dart';
import 'package:xpense_app/core/ui/gallery/gallery_page.dart';

/// The routes one feature contributes, exported from its `routes.dart`.
///
/// Features add screens there, so the central router is never edited again
/// (DELEGATION, "Order and parallelism").
@immutable
final class FeatureRoutes {
  /// Creates a feature's routes.
  const new({this.branch, this.routes = const []});

  /// The feature's tab branch; only Home, Activity, Goals and Accounts
  /// have one.
  final StatefulShellBranch? branch;

  /// Screens pushed above the shell, on the root navigator, so the tab bar
  /// is hidden while they show.
  final List<RouteBase> routes;
}

/// Everything the router is built from: the four tabs in order and every
/// other feature's routes.
@immutable
final class AppRouteTable {
  /// Creates the table. Each tab's [FeatureRoutes] must have a branch.
  const new({
    required this.home,
    required this.activity,
    required this.goals,
    required this.accounts,
    this.others = const [],
  });

  /// Home tab.
  final FeatureRoutes home;

  /// Activity tab.
  final FeatureRoutes activity;

  /// Goals tab.
  final FeatureRoutes goals;

  /// Accounts tab.
  final FeatureRoutes accounts;

  /// Features without a tab.
  final List<FeatureRoutes> others;

  /// The tabs in [AppTab] order.
  List<FeatureRoutes> get tabs => [home, activity, goals, accounts];
}

/// A rule that may send a location elsewhere, such as the sign-in gate:
/// returns the new location, or null to let it pass. It must be pure and
/// must not send a location to one it would rewrite again.
typedef RouteGuard = String? Function(Uri location);

/// Builds the app's one router (ARCHITECTURE 3.3).
///
/// The four tabs share a `StatefulShellRoute.indexedStack`, so each keeps
/// its stack and scroll position. Every other screen, Ask included, is a
/// top-level route pushed above the shell. Incoming `xpense://` links are
/// rewritten by [appRedirect]. Debug builds add the component gallery at
/// [AppRoutes.gallery]; release builds never contain the route.
///
/// [guard] runs after [appRedirect] on every location, and again whenever
/// [refreshListenable] notifies; the root passes the onboarding gate here
/// (WP-11), so a feature never builds its own router.
GoRouter buildAppRouter(
  AppRouteTable table, {
  String initialLocation = AppRoutes.home,
  List<NavigatorObserver>? observers,
  RouteGuard? guard,
  Listenable? refreshListenable,
}) {
  final tabs = table.tabs;
  assert(
    tabs.every((t) => t.branch != null),
    'Each of the four tabs needs a branch in its FeatureRoutes.',
  );
  return GoRouter(
    initialLocation: initialLocation,
    observers: observers,
    refreshListenable: refreshListenable,
    // A deep link is rewritten first; go_router then runs this again on
    // the rewritten location, where the guard applies.
    redirect: (context, state) =>
        appRedirect(state.uri) ?? guard?.call(state.uri),
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [for (final tab in tabs) tab.branch!],
      ),
      for (final feature in [...tabs, ...table.others]) ...feature.routes,
      GoRoute(
        path: AppRoutes.notFound,
        builder: (context, state) => const NotFoundScreen(),
      ),
      if (kDebugMode)
        GoRoute(
          path: AppRoutes.gallery,
          pageBuilder: (context, state) =>
              xpPage(context, state, const GalleryPage()),
        ),
    ],
  );
}

/// The router's only redirect. Pure: it reads the URI and nothing else.
///
/// - `xpense://…` deep links become the location they open, or
///   [AppRoutes.notFound] when they open nothing.
/// - `/` goes to Home.
/// - Everything else passes. No rule redirects to a location that another
///   rule rewrites, so there are no loops.
String? appRedirect(Uri uri) {
  if (uri.scheme.toLowerCase() == DeepLink.scheme) {
    return DeepLink.parse(uri)?.location ?? AppRoutes.notFound;
  }
  if (uri.path.isEmpty || uri.path == '/') return AppRoutes.home;
  return null;
}
