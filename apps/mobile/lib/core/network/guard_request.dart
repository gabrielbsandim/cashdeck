import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/network/api_error_mapper.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:dio/dio.dart';

Future<Result<T>> guardRequest<T>(Future<T> Function() request) async {
  try {
    return Ok(await request());
  } on DioException catch (exception) {
    return Err(mapDioException(exception));
  } on FormatException {
    return Err<T>(const UnexpectedFailure());
  }
}
