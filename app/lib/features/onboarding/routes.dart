import 'package:go_router/go_router.dart';

import 'package:xpense_app/core/l10n/l10n.dart';
import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/features/onboarding/create_account_screen.dart';
import 'package:xpense_app/features/onboarding/email_screen.dart';
import 'package:xpense_app/features/onboarding/email_view_model.dart';
import 'package:xpense_app/features/onboarding/onboarding_gate.dart';
import 'package:xpense_app/features/onboarding/try_it_screen.dart';
import 'package:xpense_app/features/onboarding/welcome_screen.dart';

/// Routes of the Onboarding feature: Welcome, Create account, the email
/// form and Try it (screens 1, 2 and 5), plus the Terms and Privacy Policy
/// that Create account links to.
///
/// Who may open which is decided by [onboardingRedirect], which the root
/// passes to the router through [onboardingGateProvider].
FeatureRoutes onboardingRoutes() => FeatureRoutes(
  routes: [
    GoRoute(
      path: OnboardingRoutes.welcome,
      pageBuilder: (context, state) =>
          xpPage(context, state, WelcomeScreen(inviteCode: _code(state))),
      routes: [
        GoRoute(
          path: _segment(OnboardingRoutes.createAccount),
          pageBuilder: (context, state) => xpPage(
            context,
            state,
            CreateAccountScreen(
              invite: _invite(state),
              inviteCode: _code(state),
            ),
          ),
          routes: [
            GoRoute(
              path: _segment(OnboardingRoutes.email),
              pageBuilder: (context, state) => xpPage(
                context,
                state,
                EmailScreen(
                  mode:
                      state.uri.queryParameters[OnboardingRoutes.modeParam] ==
                          OnboardingRoutes.signInMode
                      ? EmailMode.signIn
                      : EmailMode.create,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: OnboardingRoutes.tryIt,
      pageBuilder: (context, state) =>
          xpPage(context, state, const TryItScreen()),
    ),
    GoRoute(
      path: OnboardingRoutes.terms,
      pageBuilder: (context, state) => xpPage(
        context,
        state,
        PlaceholderScreen(
          title: context.l10n.onboardingTermsTitle,
          message: context.l10n.onboardingTermsPlaceholder,
          pushed: true,
        ),
      ),
    ),
    GoRoute(
      path: OnboardingRoutes.privacy,
      pageBuilder: (context, state) => xpPage(
        context,
        state,
        PlaceholderScreen(
          title: context.l10n.onboardingPrivacyTitle,
          message: context.l10n.onboardingPrivacyPlaceholder,
          pushed: true,
        ),
      ),
    ),
  ],
);

/// The last path segment of a nested route's location.
String _segment(String location) => location.split('/').last;

String? _code(GoRouterState state) =>
    state.uri.queryParameters[OnboardingRoutes.codeParam];

bool _invite(GoRouterState state) =>
    state.uri.queryParameters[OnboardingRoutes.inviteParam] == '1' ||
    _code(state) != null;
