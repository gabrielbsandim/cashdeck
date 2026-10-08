import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/network/guard_request.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wraps the value', () async {
    expect(await guardRequest(() async => 1), const Ok(1));
  });

  test('maps a Dio error', () async {
    final result = await guardRequest<int>(
      () async => throw DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ),
    );
    expect(result, const Err<int>(NetworkFailure()));
  });

  test('a body of an unexpected shape is an unexpected failure', () async {
    final result = await guardRequest<int>(
      () async => throw const FormatException('bad'),
    );
    expect(result, const Err<int>(UnexpectedFailure()));
  });
}
