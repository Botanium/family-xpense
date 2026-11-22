import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:xpense_app/data/auth_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// Whether the email form makes a new account or signs in to one.
enum EmailMode {
  /// Create an account (the default from Create account).
  create,

  /// Sign in to an existing account.
  signIn,
}

/// What is wrong with the email field.
enum EmailProblem {
  /// Nothing typed.
  empty,

  /// Not an email address.
  invalid,

  /// An account with this email exists (creating).
  inUse,
}

/// What is wrong with the password field.
enum PasswordProblem {
  /// Nothing typed.
  empty,

  /// Shorter than [minPasswordLength] (creating).
  short,

  /// Firebase's password policy rejected it (creating).
  weak,

  /// The email and password do not match (signing in).
  wrong,
}

/// Shortest new password the form accepts; Firebase's default policy.
const int minPasswordLength = 6;

final RegExp _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Checks the email before it is sent; null when it looks right. Firebase
/// has the last word.
EmailProblem? checkEmail(String email) {
  final text = email.trim();
  if (text.isEmpty) return EmailProblem.empty;
  return _emailShape.hasMatch(text) ? null : EmailProblem.invalid;
}

/// Checks the password before it is sent; null when it can be tried.
PasswordProblem? checkPassword(String password, EmailMode mode) {
  if (password.isEmpty) return PasswordProblem.empty;
  if (mode == EmailMode.create && password.length < minPasswordLength) {
    return PasswordProblem.short;
  }
  return null;
}

/// What the email form shows.
@immutable
final class EmailFormState {
  /// Creates a state.
  const new({
    this.mode = EmailMode.create,
    this.busy = false,
    this.resetting = false,
    this.signedIn = false,
    this.emailProblem,
    this.passwordProblem,
    this.failure,
    this.resetSentTo,
  });

  /// Create or sign in.
  final EmailMode mode;

  /// Whether creating the account or signing in is in flight.
  final bool busy;

  /// Whether a password reset is being sent.
  final bool resetting;

  /// Whether sign-in succeeded; the router leaves the screen on its own.
  final bool signedIn;

  /// Inline message under the email field.
  final EmailProblem? emailProblem;

  /// Inline message under the password field.
  final PasswordProblem? passwordProblem;

  /// A failure that belongs to neither field (offline, too many attempts).
  final AuthFailure? failure;

  /// The address a password reset was sent to.
  final String? resetSentTo;

  /// Whether the form is disabled.
  bool get locked => busy || resetting || signedIn;

  /// Whether the offline banner shows.
  bool get offline => failure is AuthOffline;

  @override
  bool operator ==(Object other) =>
      other is EmailFormState &&
      other.mode == mode &&
      other.busy == busy &&
      other.resetting == resetting &&
      other.signedIn == signedIn &&
      other.emailProblem == emailProblem &&
      other.passwordProblem == passwordProblem &&
      other.failure == failure &&
      other.resetSentTo == resetSentTo;

  @override
  int get hashCode => Object.hash(
    mode,
    busy,
    resetting,
    signedIn,
    emailProblem,
    passwordProblem,
    failure,
    resetSentTo,
  );
}

/// The view model of the email form. Text lives in the screen's
/// controllers; this checks it, calls the repository and turns failures
/// into field messages.
final class EmailViewModel extends Notifier<EmailFormState> {
  /// Creates the view model for a form opened in [initialMode].
  new(this.initialMode);

  /// The mode the route opened the form in.
  final EmailMode initialMode;

  @override
  EmailFormState build() => EmailFormState(mode: initialMode);

  /// Switches between creating and signing in, clearing every message.
  void toggleMode() {
    if (state.locked) return;
    state = EmailFormState(
      mode: state.mode == EmailMode.create
          ? EmailMode.signIn
          : EmailMode.create,
    );
  }

  /// Clears the email field's message once the person edits it.
  void emailEdited() {
    if (state.emailProblem == null && state.resetSentTo == null) return;
    state = EmailFormState(
      mode: state.mode,
      passwordProblem: state.passwordProblem,
      failure: state.failure,
    );
  }

  /// Clears the password field's message once the person edits it.
  void passwordEdited() {
    if (state.passwordProblem == null) return;
    state = EmailFormState(
      mode: state.mode,
      emailProblem: state.emailProblem,
      failure: state.failure,
      resetSentTo: state.resetSentTo,
    );
  }

  /// Checks the fields, then creates the account or signs in.
  Future<void> submit({required String email, required String password}) async {
    if (state.locked) return;
    final mode = state.mode;
    final emailProblem = checkEmail(email);
    final passwordProblem = checkPassword(password, mode);
    if (emailProblem != null || passwordProblem != null) {
      state = EmailFormState(
        mode: mode,
        emailProblem: emailProblem,
        passwordProblem: passwordProblem,
      );
      return;
    }
    state = EmailFormState(mode: mode, busy: true);
    final auth = ref.read(authRepositoryProvider);
    final result = mode == EmailMode.create
        ? await auth.createAccountWithEmail(email: email, password: password)
        : await auth.signInWithEmail(email: email, password: password);
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => EmailFormState(mode: mode, signedIn: true),
      Err(:final failure) => _failed(mode, failure),
    };
  }

  /// Sends a password reset to [email], after checking it.
  Future<void> forgotPassword(String email) async {
    if (state.locked) return;
    final mode = state.mode;
    final problem = checkEmail(email);
    if (problem != null) {
      state = EmailFormState(mode: mode, emailProblem: problem);
      return;
    }
    state = EmailFormState(mode: mode, resetting: true);
    final result = await ref
        .read(authRepositoryProvider)
        .sendPasswordReset(email: email);
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => EmailFormState(mode: mode, resetSentTo: email.trim()),
      Err(:final failure) => _failed(mode, failure),
    };
  }

  static EmailFormState _failed(EmailMode mode, AuthFailure failure) =>
      switch (failure) {
        AuthInvalidEmail() => EmailFormState(
          mode: mode,
          emailProblem: EmailProblem.invalid,
        ),
        AuthEmailInUse() => EmailFormState(
          mode: mode,
          emailProblem: EmailProblem.inUse,
        ),
        AuthWeakPassword() => EmailFormState(
          mode: mode,
          passwordProblem: PasswordProblem.weak,
        ),
        AuthWrongCredentials() => EmailFormState(
          mode: mode,
          passwordProblem: PasswordProblem.wrong,
        ),
        AuthCancelled() => EmailFormState(mode: mode),
        AuthOffline() ||
        AuthTooManyAttempts() ||
        AuthAccountDisabled() ||
        AuthOtherMethod() ||
        AuthMethodUnavailable() ||
        AuthUnknown() => EmailFormState(mode: mode, failure: failure),
      };
}

/// The email form's view model by the mode the route opened it in,
/// disposed with the screen.
final NotifierProviderFamily<EmailViewModel, EmailFormState, EmailMode>
emailViewModelProvider = NotifierProvider.autoDispose
    .family<EmailViewModel, EmailFormState, EmailMode>(
      EmailViewModel.new,
      name: 'emailViewModelProvider',
    );
