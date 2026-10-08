import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/domain/account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final FutureProvider<ServerInfo> serverInfoProvider =
    FutureProvider.autoDispose<ServerInfo>(
      (ref) async =>
          (await ref.watch(accountRepositoryProvider).server()).orThrow,
      retry: noRetry,
    );

final FutureProvider<UserSession> sessionProvider =
    FutureProvider.autoDispose<UserSession>(
      (ref) async =>
          (await ref.watch(accountRepositoryProvider).session()).orThrow,
      retry: noRetry,
    );
