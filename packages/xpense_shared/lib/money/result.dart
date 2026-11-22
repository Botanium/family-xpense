/// A typed success-or-failure value for recoverable failures.
///
/// Pure functions in this package never throw for expected bad input (an
/// unknown currency code, a malformed rate). They return a [Result] whose
/// failure arm is a sealed family with a stable `code`, so callers switch on
/// it exhaustively and localise from the code at the presentation edge.
library;

import 'package:meta/meta.dart';

/// A recoverable failure. Each boundary owns one sealed family of these.
///
/// [code] is stable and localisation-key-like (for example
/// `money.unknown_currency`). A failure never carries a user-facing string.
abstract interface class Failure {
  /// The stable machine code of this failure.
  String get code;
}

/// Either an [Ok] holding a value or an [Err] holding a typed failure.
@immutable
sealed class Result<T, F extends Failure> {
  const new();
}

/// The success arm of a [Result].
final class Ok<T, F extends Failure> extends Result<T, F> {
  /// Wraps a successful [value].
  const new(this.value);

  /// The successful value.
  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, F> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

/// The failure arm of a [Result].
final class Err<T, F extends Failure> extends Result<T, F> {
  /// Wraps a typed [failure].
  const new(this.failure);

  /// The typed failure.
  final F failure;

  @override
  bool operator ==(Object other) =>
      other is Err<T, F> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err(${failure.code})';
}

/// Convenience accessors for [Result].
extension ResultX<T, F extends Failure> on Result<T, F> {
  /// Folds both arms into one value.
  R fold<R>(R Function(T value) onOk, R Function(F failure) onErr) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };

  /// Maps the success value, keeping a failure as is.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final failure) => Err(failure),
  };

  /// Chains another fallible step after a success.
  Result<R, F> flatMap<R>(Result<R, F> Function(T value) next) =>
      switch (this) {
        Ok(:final value) => next(value),
        Err(:final failure) => Err(failure),
      };

  /// The success value, or `null` for a failure.
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  /// The failure, or `null` for a success.
  F? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  /// Whether this is a success.
  bool get isOk => this is Ok<T, F>;
}
