import 'dart:typed_data';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/bills/bills_providers.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/receipts/data/fake_receipts_repository.dart';
import 'package:cashdeck/features/receipts/domain/receipt.dart';
import 'package:cashdeck/features/receipts/presentation/receipt_viewer_screen.dart';
import 'package:cashdeck/features/receipts/receipts_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _Attached implements ReceiptsRepository {
  bool fail = false;

  @override
  Future<Result<Receipt>> receipt(String billId) async {
    if (fail) return const Err(NetworkFailure());
    return Ok(
      Receipt(
        billId: billId,
        attachments: [Attachment(id: 'a', fileName: '$billId.pdf')],
      ),
    );
  }

  @override
  Future<Result<LocalFile>> document(String billId) async =>
      const Err(NotFoundFailure());

  @override
  Future<Result<Receipt>> attach(String billId, LocalFile file) async =>
      const Err(NetworkFailure());
}

void main() {
  test('only the condominium bill carries a bank proof', () async {
    final repository = FakeReceiptsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );

    final condo = (await repository.receipt('bill-condo') as Ok<Receipt>).value;
    expect(condo.proof?.amount, const Money(78_000));
    expect(condo.proof?.paidAt, DateTime.utc(2026, 10, 5, 10, 2, 14));
    expect(condo.proof?.props, hasLength(7));
    expect(condo.props, hasLength(3));
    expect(
      await repository.receipt('bill-gym'),
      const Ok(Receipt(billId: 'bill-gym')),
    );
    expect(const Attachment(id: 'a', fileName: 'f').props, ['a', 'f']);
  });

  test('the provider reads the fake', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(receiptsRepositoryProvider),
      isA<FakeReceiptsRepository>(),
    );
  });

  testWidgets('shows the bank proof and offers to share it', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.bills);
    app.router.push(AppRoutes.billReceipt('bill-condo')).ignore();
    await settle(tester);

    expect(find.text(l10n.receiptPaidAutomatic), findsOneWidget);
    expect(find.text('E12345678202610050702a9c4f3d1'), findsOneWidget);
    expect(find.text('05/10/2026 · 07:02:14'), findsOneWidget);
    expect(find.text(l10n.attachAnotherButton), findsOneWidget);

    final sharer = app.read(fileSharerProvider) as FakeFileSharer;
    await tester.tap(find.byKey(ReceiptViewerScreen.shareKey));
    await settle(tester);
    await tester.tap(find.byKey(ReceiptViewerScreen.pdfKey));
    await settle(tester);
    await tester.tap(find.byTooltip(l10n.shareButton));
    await settle(tester);
    expect(sharer.texts, hasLength(2));
    expect(sharer.texts.first, contains('E12345678202610050702a9c4f3d1'));
    expect(sharer.files.single.name, 'comprovante-bill-condo.pdf');
    expect(String.fromCharCodes(sharer.files.single.bytes.take(5)), '%PDF-');

    await tester.tap(find.byKey(ReceiptViewerScreen.attachmentsTabKey));
    await settle(tester);
    expect(find.text(l10n.receiptNoAttachments), findsOneWidget);

    await tester.tap(find.byTooltip('Fechar'));
    await settle(tester);
    expect(app.location, AppRoutes.bills);
  });

  testWidgets('a bill paid by hand has no proof but takes a file', (
    tester,
  ) async {
    final bills = FakeBillsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    await tester.runAsync(() => bills.markPaid('bill-internet'));
    final chooser = FakeFileChooser(
      LocalFile(name: 'recibo.pdf', bytes: Uint8List(8)),
    );
    final app = await pumpRoute(
      tester,
      AppRoutes.billReceipt('bill-internet'),
      overrides: [
        billsRepositoryProvider.overrideWithValue(bills),
        fileChooserProvider.overrideWithValue(chooser),
      ],
    );

    expect(find.text(l10n.receiptPaidByYou), findsOneWidget);
    expect(find.text(l10n.receiptNoAttachments), findsOneWidget);

    await tester.tap(find.text(l10n.receiptFromBank));
    await settle(tester);
    expect(find.text(l10n.receiptNoProofTitle), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.shareButton));
    await settle(tester);
    expect(
      (app.read(fileSharerProvider) as FakeFileSharer).texts.single,
      contains('Internet Fibra Sul'),
    );

    await tester.tap(find.byKey(ReceiptViewerScreen.attachKey));
    await settle(tester);
    expect(find.text(l10n.attachedToast('recibo.pdf')), findsOneWidget);
    await waitForToast(tester);
    await tester.tap(find.byKey(ReceiptViewerScreen.attachmentsTabKey));
    await settle(tester);
    expect(find.text('recibo.pdf'), findsOneWidget);

    chooser.next = null;
    await tester.tap(find.byKey(ReceiptViewerScreen.attachKey));
    await settle(tester);
    expect(chooser.requests, hasLength(2));
  });

  testWidgets('lists the files of an unpaid bill', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.billReceipt('bill-rent'),
      overrides: [receiptsRepositoryProvider.overrideWithValue(_Attached())],
    );

    expect(find.text('bill-rent.pdf'), findsOneWidget);
    expect(find.text(l10n.receiptAttachments(1)), findsOneWidget);
    expect(find.text(l10n.attachFileButton), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    final receipts = _Attached()..fail = true;
    await pumpRoute(
      tester,
      AppRoutes.billReceipt('bill-rent'),
      overrides: [receiptsRepositoryProvider.overrideWithValue(receipts)],
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    receipts.fail = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    expect(find.text('bill-rent.pdf'), findsOneWidget);
  });
}
