import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/invoices/data/fake_issuer_repository.dart';
import 'package:cashdeck/features/invoices/domain/issuer_setup.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No issuer endpoint yet, so both backends read the fake.
final issuerRepositoryProvider = Provider<IssuerRepository>(
  (ref) => FakeIssuerRepository(ref.watch(clockProvider)),
);
