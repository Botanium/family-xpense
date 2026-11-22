import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/core/routing/routing.dart';
import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_app/data/household_repository.dart';

/// Locations of the onboarding screens (DESIGN_SYSTEM 9, screens 1, 2 and
/// 5). Identity travels in the query, never in `extra`, so a cold start
/// rebuilds the flow from the URL.
///
/// Welcome, Create account and the email form are nested routes opened
/// with `context.go`, so the stack is rebuilt from the path (the back
/// swipe works) and the router's redirect always sees the whole query,
/// which is how the invite path survives signing in.
abstract final class OnboardingRoutes {
  /// Welcome (screen 1). Optional query: [codeParam] from an invite link.
  static const String welcome = '/welcome';

  /// Create account (screen 2): Apple, Google, email.
  static const String createAccount = '/welcome/account';

  /// The email and password form behind "Continue with email".
  static const String email = '/welcome/account/email';

  /// Try it (screen 5): the first capture, after household setup.
  static const String tryIt = AppRoutes.tryIt;

  /// Terms of Service, linked from Create account.
  static const String terms = '/legal/terms';

  /// Privacy Policy, linked from Create account.
  static const String privacy = '/legal/privacy';

  /// Query parameter set to `1` when the person came to join a partner's
  /// household; after signing in they go to the join screen.
  static const String inviteParam = 'invite';

  /// Query parameter holding an invite code from an `xpense://join` link.
  static const String codeParam = AppRoutes.codeParam;

  /// Query parameter of the email form: `signin` for an existing account.
  static const String modeParam = 'mode';

  /// Value of [modeParam] for signing in.
  static const String signInMode = 'signin';

  /// Welcome, keeping an invite [code] from a link.
  static String welcomeWith({String? code}) => _with(welcome, code: code);

  /// Create account; [invite] when joining a partner.
  static String createAccountWith({bool invite = false, String? code}) =>
      _with(createAccount, invite: invite, code: code);

  /// The email form; [signIn] opens it for an existing account.
  static String emailWith({
    bool invite = false,
    String? code,
    bool signIn = false,
  }) => _with(email, invite: invite, code: code, signIn: signIn);

  static String _with(
    String path, {
    bool invite = false,
    String? code,
    bool signIn = false,
  }) {
    final query = {
      if (invite) inviteParam: '1',
      if (code != null && code.isNotEmpty) codeParam: code,
      if (signIn) modeParam: signInMode,
    };
    return query.isEmpty
        ? path
        : Uri(path: path, queryParameters: query).toString();
  }
}

/// Where the person goes once signed in, from the onboarding location
/// [from], given their [membership]: the join screen when they came with
/// an invite, household setup when they have no household, Home when they
/// do. While the membership is still loading this returns null, so the
/// sign-in screen stays (showing "Signing in…") until it is known.
String? afterSignIn(Uri from, Membership membership) {
  final query = from.queryParameters;
  final code = query[OnboardingRoutes.codeParam];
  if (code != null && code.isNotEmpty) return AppRoutes.joinWith(code: code);
  if (query[OnboardingRoutes.inviteParam] == '1') return AppRoutes.join;
  return switch (membership) {
    MembershipUnknown() => null,
    NoHousehold() => AppRoutes.householdSetup,
    InHousehold() => AppRoutes.home,
  };
}

/// Locations anyone may open, signed in or not.
const Set<String> _openToAll = {
  OnboardingRoutes.terms,
  OnboardingRoutes.privacy,
  AppRoutes.notFound,
  AppRoutes.gallery,
};

bool _isSignedOutOnly(String path) =>
    path == OnboardingRoutes.welcome ||
    path.startsWith('${OnboardingRoutes.welcome}/');

/// Locations a signed-in person without a household may open: setting one
/// up and joining one.
bool _isHouseholdlessAllowed(String path) =>
    path == AppRoutes.householdSetup ||
    path.startsWith('${AppRoutes.householdSetup}/') ||
    path == AppRoutes.join;

/// The sign-in and household rule of the router (BACKLOG S1.3, S1.4).
/// Pure: it reads the location, whether someone is signed in and their
/// [membership], nothing else.
///
/// - Signed out: Welcome and its sign-in screens are open; a join link
///   keeps its code on the way to Welcome; everything else goes to Welcome.
/// - Signed in: the signed-out screens give way to [afterSignIn], which is
///   how a successful sign-in leaves them.
/// - Signed in without a household: only household setup and joining are
///   open; everything else goes to household setup.
/// - Otherwise everything passes. A member may still open setup (to share
///   the invite) and the join screen (its success state).
///
/// No rule sends a location to one another rule rewrites, so no loops.
String? onboardingRedirect(
  Uri uri, {
  required bool signedIn,
  Membership membership = const MembershipUnknown(),
}) {
  final path = uri.path;
  if (_openToAll.contains(path)) return null;
  if (!signedIn) {
    if (_isSignedOutOnly(path)) return null;
    if (path == AppRoutes.join) {
      return OnboardingRoutes.welcomeWith(
        code: uri.queryParameters[AppRoutes.codeParam],
      );
    }
    return OnboardingRoutes.welcome;
  }
  if (_isSignedOutOnly(path)) return afterSignIn(uri, membership);
  if (membership is NoHousehold && !_isHouseholdlessAllowed(path)) {
    return AppRoutes.householdSetup;
  }
  return null;
}

/// Feeds [onboardingRedirect] with the sign-in state and the household
/// membership, and tells the router to run it again whenever either
/// changes.
final class OnboardingGate extends ChangeNotifier {
  /// Watches the sign-in state of an [AuthRepository] and the membership
  /// of a [HouseholdRepository].
  new(this._auth, this._households)
    : _signedIn = _auth.currentUser != null,
      _membership = _households.current {
    _subscription = _auth.authStateChanges().listen(_onUser);
    _membershipSubscription = _households.watchMembership().listen(
      _onMembership,
    );
  }

  final AuthRepository _auth;
  final HouseholdRepository _households;
  late final StreamSubscription<AuthUser?> _subscription;
  late final StreamSubscription<Membership> _membershipSubscription;
  bool _signedIn;
  Membership _membership;

  /// The router guard. Reads the repositories, which know the session and
  /// the membership before their change events arrive.
  String? redirect(Uri uri) => onboardingRedirect(
    uri,
    signedIn: _auth.currentUser != null,
    membership: _households.current,
  );

  void _onUser(AuthUser? user) {
    final signedIn = user != null;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    notifyListeners();
  }

  // Only the kind of membership moves the router; a renamed household or a
  // partner joining does not.
  void _onMembership(Membership membership) {
    final changed = membership.runtimeType != _membership.runtimeType;
    _membership = membership;
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_membershipSubscription.cancel());
    super.dispose();
  }
}

/// The app's [OnboardingGate]; the root passes it to the router.
final onboardingGateProvider = Provider<OnboardingGate>((ref) {
  final gate = OnboardingGate(
    ref.watch(authRepositoryProvider),
    ref.watch(householdRepositoryProvider),
  );
  ref.onDispose(gate.dispose);
  return gate;
}, name: 'onboardingGateProvider');
