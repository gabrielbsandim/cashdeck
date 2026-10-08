import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';

/// Carries an [AppFailure] through an `AsyncValue` error.
final class LoadFailure implements Exception {
  const new(this.failure);

  final AppFailure failure;

  @override
  String toString() => 'LoadFailure($failure)';
}

AppFailure failureOf(Object? error) => switch (error) {
  LoadFailure(:final failure) => failure,
  _ => const UnexpectedFailure(),
};

/// Screens offer their own retry button, so a failed load stays failed.
Duration? noRetry(int retryCount, Object error) => null;

extension LoadedResult<T> on Result<T> {
  /// The value, or a [LoadFailure] for an `AsyncValue` to hold.
  T get orThrow => switch (this) {
    Ok(:final value) => value,
    Err(:final failure) => throw LoadFailure(failure),
  };
}
