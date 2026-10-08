import 'package:cashdeck/core/config/app_config.dart';
import 'package:dio/dio.dart';

BaseOptions apiBaseOptions(AppConfig config) => BaseOptions(
  baseUrl: config.apiBaseUrl,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 30),
  contentType: Headers.jsonContentType,
  headers: {'X-Client': 'mobile'},
);

Dio createApiDio(AppConfig config) => Dio(apiBaseOptions(config));
