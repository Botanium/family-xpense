import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/core/theme/theme.dart';
import 'package:xpense_app/core/ui/ui.dart';
import 'package:xpense_app/data/fx_repository.dart';
import 'package:xpense_app/features/accounts/routes.dart';
import 'package:xpense_app/features/activity/routes.dart';
import 'package:xpense_app/features/ask/routes.dart';
import 'package:xpense_app/features/budgets/routes.dart';
import 'package:xpense_app/features/capture/routes.dart';
import 'package:xpense_app/features/goals/routes.dart';
import 'package:xpense_app/features/home/routes.dart';
import 'package:xpense_app/features/household/routes.dart';
import 'package:xpense_app/features/insights/routes.dart';
import 'package:xpense_app/features/loans/routes.dart';
import 'package:xpense_app/features/notifications/routes.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';
import 'package:xpense_app/features/onboarding/routes.dart';
import 'package:xpense_app/features/settings_privacy/lock/app_lock_controller.dart';
import 'package:xpense_app/features/settings_privacy/lock/app_lock_gate.dart';
import 'package:xpense_app/features/settings_privacy/routes.dart';
import 'package:xpense_app/services/feature_flags.dart';
import 'package:xpense_app/services/on_device_llm/on_device_llm.dart';
import 'package:xpense_app/services/settings_store.dart';

/// Every feature's routes. Features change their own `routes.dart`; this
/// list changes only when a feature folder is added.
AppRouteTable appRouteTable() => AppRouteTable(
  home: homeRoutes(),
  activity: activityRoutes(),
  goals: goalsRoutes(),
  accounts: accountsRoutes(),
  others: [
    askRoutes(),
    settingsPrivacyRoutes(),
    onboardingRoutes(),
    householdRoutes(),
    captureRoutes(),
    loansRoutes(),
    budgetsRoutes(),
    insightsRoutes(),
    notificationsRoutes(),
  ],
);

/// The routes the router is built from; tests may narrow them.
final appRouteTableProvider = Provider<AppRouteTable>(
  (ref) => appRouteTable(),
  name: 'appRouteTableProvider',
);

/// The app's one router, behind the onboarding gate: signed out, only
/// Welcome and its sign-in screens open (WP-11).
final routerProvider = Provider<GoRouter>((ref) {
  final gate = ref.watch(onboardingGateProvider);
  final router = buildAppRouter(
    ref.watch(appRouteTableProvider),
    guard: gate.redirect,
    refreshListenable: gate,
  );
  ref.onDispose(router.dispose);
  return router;
}, name: 'routerProvider');

/// The glass tier for the session, chosen at startup (DESIGN_SYSTEM 6.2).
/// Throws until the composition root sets it.
final glassControllerProvider = Provider<GlassController>(
  (ref) =>
      throw UnimplementedError('glassControllerProvider is set in bootstrap()'),
  name: 'glassControllerProvider',
);

/// Maps the stored appearance to Flutter's theme mode.
ThemeMode themeModeFor(AppearanceMode appearance) => switch (appearance) {
  AppearanceMode.system => ThemeMode.system,
  AppearanceMode.light => ThemeMode.light,
  AppearanceMode.dark => ThemeMode.dark,
};

/// The root widget: theme, strings, router, glass tier and the lock.
///
/// It names no concrete service; everything comes from providers that the
/// composition root (`bootstrap.dart`) or a test overrides. It owns the one
/// app lifecycle observer and starts the post-frame work of ARCHITECTURE
/// 3.3.
class XpenseApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const new({super.key});

  @override
  ConsumerState<XpenseApp> createState() => _XpenseAppState();
}

class _XpenseAppState extends ConsumerState<XpenseApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  // The one lifecycle observer. Packages that must flush state before the
  // app can be killed add their call here (app-startup rule 11).
  void _onLifecycle(AppLifecycleState state) {
    ref.read(appLockControllerProvider.notifier).onLifecycle(state);
    // Back from the background, perhaps on another day: the daily rate's
    // day reads the clock again (WP-24, review on PR #42).
    if (state == AppLifecycleState.resumed) {
      ref.read(rateTodayProvider.notifier).refresh();
    }
  }

  // After the first frame, best effort, never awaited (ARCHITECTURE 3.3).
  // Remote Config fetch (WP-01) and the rule cache sync (WP-34) join here.
  void _afterFirstFrame() {
    if (!mounted) return;
    // Remote Config: fetch, activate, then follow console changes (D-39).
    unawaited(
      ref
          .read(featureFlagSourceProvider)
          .refresh()
          .then<void>((_) {}, onError: _log),
    );
    unawaited(
      ref.read(onDeviceProbeProvider.future).then<void>((_) {}, onError: _log),
    );
  }

  void _log(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(exception: error, stack: stack, library: 'XpenseApp'),
  );

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(
      appSettingsProvider.select((s) => s.appearance),
    );
    return GlassScope(
      controller: ref.watch(glassControllerProvider),
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (context) => context.l10n.appTitle,
        theme: XpThemes.light,
        darkTheme: XpThemes.dark,
        highContrastTheme: XpThemes.lightHighContrast,
        highContrastDarkTheme: XpThemes.darkHighContrast,
        themeMode: themeModeFor(appearance),
        themeAnimationStyle: xpThemeAnimationStyle,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) => _SystemBars(
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}

/// Status bar icons that contrast with the theme in use, which may differ
/// from the phone's own appearance.
class _SystemBars extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    child: child,
  );
}
