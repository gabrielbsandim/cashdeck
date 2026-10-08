import 'package:cashdeck/core/error/app_failure.dart';
import 'package:dio/dio.dart';

AppFailure mapDioException(DioException exception) {
  return switch (exception.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => const NetworkFailure(),
    DioExceptionType.badResponse => _mapResponse(exception.response),
    _ => const UnexpectedFailure(),
  };
}

AppFailure _mapResponse(Response<dynamic>? response) {
  final status = response?.statusCode ?? 0;
  final message = _serverMessage(response?.data);
  return switch (status) {
    400 || 409 || 422 when message != null => ValidationFailure(message),
    401 => const UnauthorizedFailure(),
    403 => const ForbiddenFailure(),
    404 => const NotFoundFailure(),
    429 => const RateLimitedFailure(),
    >= 500 => const ServerFailure(),
    _ => const UnexpectedFailure(),
  };
}

/// The API answers errors as `{ "error": { "code", "message", "details" } }`.
String? _serverMessage(Object? data) {
  if (data is! Map) return null;
  final error = data['error'];
  if (error is! Map) return null;
  final message = error['message'];
  return message is String ? message : null;
}
