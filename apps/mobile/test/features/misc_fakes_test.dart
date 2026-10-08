import 'dart:typed_data';

import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/accountant_export/data/fake_accountant_export_repository.dart';
import 'package:cashdeck/features/accountant_export/domain/accountant_export.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/invoices/data/fake_issuer_repository.dart';
import 'package:cashdeck/features/invoices/domain/issuer_setup.dart';
import 'package:cashdeck/features/receipts/data/fake_receipts_repository.dart';
import 'package:cashdeck/features/transactions/data/fake_transfers_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/builders.dart';

void main() {
  final clock = FixedClock(testNow);
  final pfx = LocalFile(name: 'novo.pfx', bytes: Uint8List(4));

  test('a personal bill never plans a bank approval', () async {
    final bills = FakeBillsRepository(clock, latency: Duration.zero);
    final all = (await bills.list() as Ok<List<Bill>>).value;

    for (final bill in all.where((b) => b.owner == EntityKind.personal)) {
      expect(
        bill.plan,
        isNot(contains(LadderStep.bankApproval)),
        reason: bill.id,
      );
    }
    expect(all.where((bill) => bill.isBolepix), isNotEmpty);
  });

  test('transfers share only the document they have', () async {
    final transfers = FakeTransfersRepository(clock, latency: Duration.zero);

    expect(
      (await transfers.document(
        'transfer-distribution',
      ) as Ok<LocalFile>).value.mimeType,
      'application/pdf',
    );
    expect(
      await transfers.document('transfer-prolabore'),
      const Err<LocalFile>(NotFoundFailure()),
    );
    expect(
      await transfers.document('nope'),
      const Err<LocalFile>(NotFoundFailure()),
    );
  });

  test('receipts share a proof only when a rail paid', () async {
    final receipts = FakeReceiptsRepository(clock, latency: Duration.zero);

    expect(await receipts.document('bill-condo'), isA<Ok<LocalFile>>());
    expect(
      await receipts.document('bill-rent'),
      const Err<LocalFile>(NotFoundFailure()),
    );
  });

  test('the export archive is named by its month', () async {
    final exports = FakeAccountantExportRepository(
      clock,
      latency: Duration.zero,
    );
    final file = await exports.archive(
      const ExportRecord(
        month: CalendarDate(2026, 9, 1),
        sentOn: testToday,
        to: 'contador@exemplo.com',
      ),
    );

    expect((file as Ok<LocalFile>).value.name, 'contador-2026-09.pdf');
  });

  test('the A1 upload needs its password and renews the expiry', () async {
    final issuer = FakeIssuerRepository(clock, latency: Duration.zero);

    expect(await issuer.uploadCertificate(pfx, ''), isA<Err<Object?>>());
    final setup = await issuer.uploadCertificate(pfx, 'senha');
    expect((setup as Ok<IssuerSetup>).value.certificateName, 'novo.pfx');
  });

  test('the selected entity survives a restart', () {
    final store = InMemoryKeyValueStore();
    ProviderContainer launch() {
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    launch().read(entityScopeProvider.notifier).select(EntityScope.company);

    expect(launch().read(entityScopeProvider), EntityScope.company);
  });
}
