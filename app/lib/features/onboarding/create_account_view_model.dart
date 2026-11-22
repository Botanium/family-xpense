import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// A sign-in method on Create account that signs in right away.
enum ProviderMethod {
  /// Sign in with Apple.
  apple,

  /// Sign in with Google.
  google,
}

/// What Create account shows (DESIGN_SYSTEM 9, screen 2).
@immutable
final class CreateAccountState {
  /// Creates a state; the default is idle with nothing to report.
  const new({this.busy, this.failure, this.last, this.signedIn = false});

  /// The method being tried, while its sheet is open.
  final ProviderMethod? busy;

  /// Why the last attempt failed; null after a success or a cancel.
  final AuthFailure? failure;

  /// The last method tried, for "Try again".
  final ProviderMethod? last;

  /// Whether sign-in succeeded. The router leaves the screen on its own;
  /// until it does, the buttons stay disabled.
  final bool signedIn;

  /// Whether the buttons are disabled.
  bool get locked => busy != null || signedIn;

  /// Whether the offline banner shows.
  bool get offline => failure is AuthOffline;

  @override
  bool operator ==(Object other) =>
      other is CreateAccountState &&
      other.busy == busy &&
      other.failure == failure &&
      other.last == last &&
      other.signedIn == signedIn;

  @override
  int get hashCode => Object.hash(busy, failure, last, signedIn);
}

/// The view model of Create account: one attempt at a time, the failure
/// kept for the inline message, a cancel shown as nothing.
final class CreateAccountViewModel extends Notifier<CreateAccountState> {
  @override
  CreateAccountState build() => const CreateAccountState();

  /// Signs in with [method]. Ignored while another attempt runs.
  Future<void> signIn(ProviderMethod method) async {
    if (state.locked) return;
    state = CreateAccountState(busy: method, last: method);
    final auth = ref.read(authRepositoryProvider);
    final result = switch (method) {
      ProviderMethod.apple => await auth.signInWithApple(),
      ProviderMethod.google => await auth.signInWithGoogle(),
    };
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => CreateAccountState(last: method, signedIn: true),
      Err(failure: AuthCancelled()) => CreateAccountState(last: method),
      Err(:final failure) => CreateAccountState(failure: failure, last: method),
    };
  }

  /// Repeats the last attempt, from the offline banner.
  Future<void> retry() async {
    final last = state.last;
    if (last != null) await signIn(last);
  }
}

/// Create account's view model, disposed with the screen.
final NotifierProvider<CreateAccountViewModel, CreateAccountState>
createAccountViewModelProvider =
    NotifierProvider.autoDispose<CreateAccountViewModel, CreateAccountState>(
      CreateAccountViewModel.new,
      name: 'createAccountViewModelProvider',
    );
