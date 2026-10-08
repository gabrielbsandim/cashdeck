import 'package:cashdeck/core/error/app_failure.dart';
import 'package:equatable/equatable.dart';

sealed class Result<T> extends Equatable {
  const new();
}

final class Ok<T> extends Result<T> {
  const new(this.value);

  final T value;

  @override
  List<Object?> get props => [value];
}

final class Err<T> extends Result<T> {
  const new(this.failure);

  final AppFailure failure;

  @override
  List<Object?> get props => [failure];
}
