import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/invoices/data/api_issuer_repository.dart';
import 'package:cashdeck/features/invoices/data/fake_issuer_repository.dart';
import 'package:cashdeck/features/invoices/domain/issuer_setup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final issuerRepositoryProvider = Provider<IssuerRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeIssuerRepository(ref.watch(clockProvider)),
    Backend.api => ApiIssuerRepository(ref.watch(dioProvider)),
  };
});
