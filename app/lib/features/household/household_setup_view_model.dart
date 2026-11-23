import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What is wrong with a name field.
enum NameProblem {
  /// Nothing typed.
  empty,

  /// Longer than [maxHouseholdNameLength] characters.
  tooLong,
}

/// Checks a household or display name before it is sent; null when it is
/// fine. Leading and trailing spaces do not count.
NameProblem? checkName(String text) {
  final name = text.trim();
  if (name.isEmpty) return NameProblem.empty;
  if (name.runes.length > maxHouseholdNameLength) return NameProblem.tooLong;
  return null;
}

/// Where the invite code stands, once the household exists.
@immutable
sealed class InviteStatus {
  const new();
}

/// Being made by the server.
final class InviteLoading extends InviteStatus {
  /// Creates the status.
  const new();

  @override
  bool operator ==(Object other) => other is InviteLoading;

  @override
  int get hashCode => (InviteLoading).hashCode;
}

/// Ready to share.
final class InviteReady extends InviteStatus {
  /// Wraps [invite].
  const new(this.invite);

  /// The invite.
  final HouseholdInvite invite;

  @override
  bool operator ==(Object other) =>
      other is InviteReady && other.invite == invite;

  @override
  int get hashCode => Object.hash(InviteReady, invite);
}

/// Could not be made; Try again asks again.
final class InviteFailed extends InviteStatus {
  /// Wraps [failure].
  const new(this.failure);

  /// Why.
  final HouseholdFailure failure;

  @override
  bool operator ==(Object other) =>
      other is InviteFailed && other.failure == failure;

  @override
  int get hashCode => Object.hash(InviteFailed, failure);
}

/// Not needed: the partner has joined.
final class InviteNotNeeded extends InviteStatus {
  /// Creates the status.
  const new();

  @override
  bool operator ==(Object other) => other is InviteNotNeeded;

  @override
  int get hashCode => (InviteNotNeeded).hashCode;
}

/// What household setup shows (DESIGN_SYSTEM 9, screen 3).
///
/// Two steps on one screen: the form until the household exists, then the
/// same fields read-only with the invite code under them.
@immutable
final class HouseholdSetupState {
  /// Creates a state.
  const new({
    this.currency = Currency.usd,
    this.creating = false,
    this.nameProblem,
    this.displayNameProblem,
    this.failure,
    this.household,
    this.invite,
    this.shared = false,
  });

  /// The chosen base currency; USD is preselected.
  final Currency currency;

  /// Whether the household is being created.
  final bool creating;

  /// Inline message under the household name.
  final NameProblem? nameProblem;

  /// Inline message under the person's own name.
  final NameProblem? displayNameProblem;

  /// Why creating the household failed.
  final HouseholdFailure? failure;

  /// The household, once it exists.
  final HouseholdSummary? household;

  /// The invite, once the household exists.
  final InviteStatus? invite;

  /// Whether the invite went to the share sheet at least once.
  final bool shared;

  /// Whether the household exists (the second step).
  bool get created => household != null;

  /// Whether the fields accept input.
  bool get editable => !created && !creating;

  /// Whether the offline banner shows.
  bool get offline => failure is HouseholdOffline;

  /// A copy with the given fields replaced. [failure] and the problems are
  /// cleared unless given, since every change answers them.
  HouseholdSetupState copyWith({
    Currency? currency,
    bool? creating,
    NameProblem? nameProblem,
    NameProblem? displayNameProblem,
    HouseholdFailure? failure,
    HouseholdSummary? household,
    InviteStatus? invite,
    bool? shared,
  }) => HouseholdSetupState(
    currency: currency ?? this.currency,
    creating: creating ?? this.creating,
    nameProblem: nameProblem,
    displayNameProblem: displayNameProblem,
    failure: failure,
    household: household ?? this.household,
    invite: invite ?? this.invite,
    shared: shared ?? this.shared,
  );

  @override
  bool operator ==(Object other) =>
      other is HouseholdSetupState &&
      other.currency == currency &&
      other.creating == creating &&
      other.nameProblem == nameProblem &&
      other.displayNameProblem == displayNameProblem &&
      other.failure == failure &&
      other.household == household &&
      other.invite == invite &&
      other.shared == shared;

  @override
  int get hashCode => Object.hash(
    currency,
    creating,
    nameProblem,
    displayNameProblem,
    failure,
    household,
    invite,
    shared,
  );
}

/// The view model of household setup. Text lives in the screen's
/// controllers; this checks it, creates the household, then asks for the
/// invite.
final class HouseholdSetupViewModel extends Notifier<HouseholdSetupState> {
  HouseholdRepository get _households => ref.read(householdRepositoryProvider);

  @override
  HouseholdSetupState build() {
    // A partner joining while the code shows replaces the code.
    ref.listen(membershipProvider, (_, next) {
      if (next.value case InHousehold(:final household)) {
        _onHousehold(household);
      }
    });
    // Opened again after the household was made (the app was closed, or
    // Back from the next step): straight to the invite.
    if (_households.current case InHousehold(:final household)) {
      if (household.memberCount >= 2) {
        return HouseholdSetupState(
          currency: household.baseCurrency,
          household: household,
          invite: const InviteNotNeeded(),
        );
      }
      unawaited(Future(requestInvite));
      return HouseholdSetupState(
        currency: household.baseCurrency,
        household: household,
        invite: const InviteLoading(),
      );
    }
    return const HouseholdSetupState();
  }

  void _onHousehold(HouseholdSummary household) {
    if (!state.created) return;
    state = state.copyWith(
      household: household,
      invite: household.memberCount >= 2 ? const InviteNotNeeded() : null,
      failure: state.failure,
    );
  }

  /// Picks the base currency.
  void selectCurrency(Currency currency) {
    if (!state.editable) return;
    state = state.copyWith(currency: currency);
  }

  /// Clears the household name's message once the person edits it.
  void nameEdited() {
    if (state.nameProblem == null) return;
    state = state.copyWith(
      displayNameProblem: state.displayNameProblem,
      failure: state.failure,
    );
  }

  /// Clears the display name's message once the person edits it.
  void displayNameEdited() {
    if (state.displayNameProblem == null) return;
    state = state.copyWith(
      nameProblem: state.nameProblem,
      failure: state.failure,
    );
  }

  /// Checks the fields, then creates the household and asks for an invite.
  Future<void> create({
    required String name,
    required String displayName,
  }) async {
    if (!state.editable) return;
    final nameProblem = checkName(name);
    final displayNameProblem = checkName(displayName);
    if (nameProblem != null || displayNameProblem != null) {
      state = state.copyWith(
        nameProblem: nameProblem,
        displayNameProblem: displayNameProblem,
      );
      return;
    }
    state = state.copyWith(creating: true);
    final result = await _households.create(
      name: name.trim(),
      displayName: displayName.trim(),
      baseCurrency: state.currency,
    );
    if (!ref.mounted) return;
    switch (result) {
      case Err(:final failure):
        state = state.copyWith(creating: false, failure: failure);
      case Ok(value: final id):
        final household = switch (_households.current) {
          InHousehold(:final household) when household.id == id => household,
          _ => HouseholdSummary(
            id: id,
            name: name.trim(),
            baseCurrency: state.currency,
            memberCount: 1,
            myDisplayName: displayName.trim(),
          ),
        };
        state = state.copyWith(
          creating: false,
          household: household,
          invite: const InviteLoading(),
        );
        await requestInvite();
    }
  }

  /// Asks the server for an invite code (again).
  Future<void> requestInvite() async {
    if (!state.created || state.invite is InviteNotNeeded) return;
    state = state.copyWith(invite: const InviteLoading());
    final result = await _households.createInvite();
    if (!ref.mounted) return;
    state = state.copyWith(
      invite: switch (result) {
        Ok(value: final invite) => InviteReady(invite),
        Err(failure: HouseholdFull()) => const InviteNotNeeded(),
        Err(:final failure) => InviteFailed(failure),
      },
    );
  }

  /// "Try again" on the offline banner: repeats what failed.
  Future<void> retry({required String name, required String displayName}) =>
      state.created
      ? requestInvite()
      : create(name: name, displayName: displayName);

  /// Records that the invite went to the share sheet.
  void markShared() {
    if (state.shared) return;
    state = state.copyWith(shared: true);
  }
}

/// Household setup's view model, disposed with the screen.
final NotifierProvider<HouseholdSetupViewModel, HouseholdSetupState>
householdSetupViewModelProvider =
    NotifierProvider.autoDispose<HouseholdSetupViewModel, HouseholdSetupState>(
      HouseholdSetupViewModel.new,
      name: 'householdSetupViewModelProvider',
    );
