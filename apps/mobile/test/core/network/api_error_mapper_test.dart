import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/network/api_error_mapper.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _response(int status, [Object? data]) {
  final options = RequestOptions(path: '/x');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: options,
      statusCode: status,
      data: data,
    ),
  );
}

void main() {
  const errorBody = {
    'error': {'code': 'VALIDATION', 'message': 'Valor inválido'},
  };

  test('connection problems are network failures', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    ]) {
      final exception = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: type,
      );
      expect(mapDioException(exception), const NetworkFailure());
    }
  });

  test('maps status codes', () {
    expect(
      mapDioException(_response(422, errorBody)),
      const ValidationFailure('Valor inválido'),
    );
    expect(mapDioException(_response(401)), const UnauthorizedFailure());
    expect(mapDioException(_response(403)), const ForbiddenFailure());
    expect(mapDioException(_response(404)), const NotFoundFailure());
    expect(mapDioException(_response(429)), const RateLimitedFailure());
    expect(mapDioException(_response(503)), const ServerFailure());
    expect(mapDioException(_response(418)), const UnexpectedFailure());
  });

  test('a 422 without the error envelope is unexpected', () {
    expect(mapDioException(_response(422, 'oops')), const UnexpectedFailure());
    expect(
      mapDioException(_response(422, {'error': 'flat'})),
      const UnexpectedFailure(),
    );
    expect(
      mapDioException(
        _response(422, {
          'error': {'message': 3},
        }),
      ),
      const UnexpectedFailure(),
    );
  });

  test('a cancelled request is unexpected', () {
    final exception = DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.cancel,
    );
    expect(mapDioException(exception), const UnexpectedFailure());
  });
}
