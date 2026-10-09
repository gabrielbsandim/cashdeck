import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/bills/bills_providers.dart';
import 'package:cashdeck/features/bills/data/api_bills_repository.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(Backend backend) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig(backend: backend, apiBaseUrl: 'https://x.test'),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the fake backend wires the in-memory repository', () {
    final container = _container(Backend.fake);

    expect(container.read(billsRepositoryProvider), isA<FakeBillsRepository>());
    expect(container.read(listBillsProvider), isNotNull);
    expect(container.read(getBillProvider), isNotNull);
    expect(container.read(markBillPaidProvider), isNotNull);
    expect(container.read(payBillProvider), isNotNull);
  });

  test('the api backend wires the HTTP repository', () {
    expect(
      _container(Backend.api).read(billsRepositoryProvider),
      isA<ApiBillsRepository>(),
    );
  });
}
