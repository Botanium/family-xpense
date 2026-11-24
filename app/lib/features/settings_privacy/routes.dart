import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/settings_privacy/categories/categories_screen.dart';
import 'package:xpense_app/features/settings_privacy/fx/rate_settings_screen.dart';
import 'package:xpense_app/features/settings_privacy/settings_screen.dart';

/// Routes of the Settings and privacy feature: Settings, opened from Home.
///
/// WP-24, WP-62, WP-70 and WP-82 add their Settings pages under
/// `/settings/…` here (exchange rate and categories, export, privacy mode,
/// account).
FeatureRoutes settingsPrivacyRoutes() => FeatureRoutes(
  routes: [
    GoRoute(
      path: AppRoutes.settings,
      pageBuilder: (context, state) =>
          xpPage(context, state, const SettingsScreen()),
    ),
    GoRoute(
      path: AppRoutes.settingsRate,
      pageBuilder: (context, state) =>
          xpPage(context, state, const RateSettingsScreen()),
    ),
    GoRoute(
      path: AppRoutes.settingsCategories,
      pageBuilder: (context, state) =>
          xpPage(context, state, const CategoriesScreen()),
    ),
  ],
);
