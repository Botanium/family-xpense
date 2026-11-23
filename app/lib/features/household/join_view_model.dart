import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xpense_app/data/household_repository.dart';
import 'package:xpense_app/features/household/household_setup_view_model.dart';
import 'package:xpense_shared/xpense_shared.dart';

/// What is wrong with the invite code field.
enum CodeProblem {
  /// Nothing typed.
  empty,

  /// Not 10 letters and digits (spaces and dashes aside).
  shape,
}

final RegExp _codeSeparators = RegExp(r'[\s-]');
final RegExp _codeShape = RegExp(r'^[A-Za-z0-9]{10}$');

/// Checks a typed invite code before it is sent; null when it can be
/// tried. The server has the last word (and reads O as 0, I and L as 1).
CodeProblem? checkCode(String text) {
  final code = text.replaceAll(_codeSeparators, '');
  if (code.isEmpty) return CodeProblem.empty;
  return _codeShape.hasMatch(code) ? null : CodeProblem.shape;
}

/// What the join screen shows.
@immutable
final class JoinState {
  /// Creates a state.
  const new({
    this.busy = false,
    this.codeProblem,
    this.nameProblem,
    this.failure,
    this.joined,
  });

  /// Whether the join is in flight.
  final bool busy;

  /// Inline message under the code field.
  final CodeProblem? codeProblem;

  /// Inline message under the name field.
  final NameProblem? nameProblem;

  /// Why the join failed.
  final HouseholdFailure? failure;

  /// The household, once joined.
  final JoinedHousehold? joined;

  /// Whether the fields accept input.
  bool get editable => !busy && joined == null;

  /// Whether the offline banner shows.
  bool get offline => failure is HouseholdOffline;

  @override
  bool operator ==(Object other) =>
      other is JoinState &&
      other.busy == busy &&
      other.codeProblem == codeProblem &&
      other.nameProblem == nameProblem &&
      other.failure == failure &&
      other.joined == joined;

  @override
  int get hashCode =>
      Object.hash(busy, codeProblem, nameProblem, failure, joined);
}

/// The view model of the join screen. Text lives in the screen's
/// controllers; this checks it and calls the repository.
final class JoinViewModel extends Notifier<JoinState> {
  @override
  JoinState build() => const JoinState();

  /// Clears the code field's message once the person edits it.
  void codeEdited() {
    if (state.codeProblem == null && state.failure == null) return;
    state = JoinState(nameProblem: state.nameProblem);
  }

  /// Clears the name field's message once the person edits it.
  void nameEdited() {
    if (state.nameProblem == null) return;
    state = JoinState(codeProblem: state.codeProblem, failure: state.failure);
  }

  /// Checks the fields, then joins.
  Future<void> submit({
    required String code,
    required String displayName,
  }) async {
    if (!state.editable) return;
    final codeProblem = checkCode(code);
    final nameProblem = checkName(displayName);
    if (codeProblem != null || nameProblem != null) {
      state = JoinState(codeProblem: codeProblem, nameProblem: nameProblem);
      return;
    }
    state = const JoinState(busy: true);
    final result = await ref
        .read(householdRepositoryProvider)
        .join(
          code: code.replaceAll(_codeSeparators, '').toUpperCase(),
          displayName: displayName.trim(),
        );
    if (!ref.mounted) return;
    state = switch (result) {
      Ok(value: final joined) => JoinState(joined: joined),
      Err(:final failure) => JoinState(failure: failure),
    };
  }
}

/// The join screen's view model, disposed with the screen.
final NotifierProvider<JoinViewModel, JoinState> joinViewModelProvider =
    NotifierProvider.autoDispose<JoinViewModel, JoinState>(
      JoinViewModel.new,
      name: 'joinViewModelProvider',
    );
