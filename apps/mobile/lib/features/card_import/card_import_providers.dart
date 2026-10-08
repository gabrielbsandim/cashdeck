import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/card_import/data/api_card_import_repository.dart';
import 'package:cashdeck/features/card_import/data/fake_card_import_repository.dart';
import 'package:cashdeck/features/card_import/domain/card_statement.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cardImportRepositoryProvider = Provider<CardImportRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeCardImportRepository(ref.watch(clockProvider)),
    Backend.api => ApiCardImportRepository(ref.watch(dioProvider)),
  };
});
