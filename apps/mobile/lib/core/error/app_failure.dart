import 'package:equatable/equatable.dart';

sealed class AppFailure extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

final class NetworkFailure extends AppFailure {
  const new();
}

final class UnauthorizedFailure extends AppFailure {
  const new();
}

final class ForbiddenFailure extends AppFailure {
  const new();
}

final class NotFoundFailure extends AppFailure {
  const new();
}

final class ValidationFailure extends AppFailure {
  const new(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

final class RateLimitedFailure extends AppFailure {
  const new();
}

final class ServerFailure extends AppFailure {
  const new();
}

final class UnexpectedFailure extends AppFailure {
  const new();
}
