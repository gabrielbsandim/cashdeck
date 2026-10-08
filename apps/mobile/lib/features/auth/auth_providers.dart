import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/auth/application/sign_in.dart';
import 'package:cashdeck/features/auth/data/api_server_access_repository.dart';
import 'package:cashdeck/features/auth/data/fake_server_access_repository.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final serverAccessRepositoryProvider = Provider<ServerAccessRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeServerAccessRepository(),
    Backend.api => ApiServerAccessRepository(ref.watch(dioProvider)),
  };
});

final signInProvider = Provider<SignIn>(
  (ref) => SignIn(ref.watch(serverAccessRepositoryProvider)),
);
