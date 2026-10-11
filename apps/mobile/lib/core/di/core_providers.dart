import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/network/dio_factory.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final dioProvider = Provider<Dio>((ref) {
  final session = ref.watch(serverSessionProvider);
  final dio = createApiDio(
    ref.watch(appConfigProvider),
    session: session,
    onUnauthorized: () =>
        ref.read(serverSessionProvider.notifier).signOut().ignore(),
    refuseWrites: session == null
        ? null
        : () => ref.read(safeModeLimitedProvider),
  );
  ref.onDispose(dio.close);
  return dio;
});

final clockProvider = Provider<Clock>((ref) => const SystemClock());
