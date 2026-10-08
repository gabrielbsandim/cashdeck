import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/network/dio_factory.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final dioProvider = Provider<Dio>((ref) {
  final dio = createApiDio(ref.watch(appConfigProvider));
  ref.onDispose(dio.close);
  return dio;
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());
