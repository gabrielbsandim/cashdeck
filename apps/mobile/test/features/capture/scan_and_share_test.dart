import 'dart:typed_data';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:cashdeck/core/share/share_intake.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/data/fake_capture_repository.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/capture/domain/scanned_code.dart';
import 'package:cashdeck/features/capture/presentation/capture_sources_screen.dart';
import 'package:cashdeck/features/capture/presentation/shared_file_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _StubFiles extends Fake implements CaptureRepository {
  new(this.result);

  final Result<CaptureOutcome> result;

  @override
  Future<Result<CaptureOutcome>> submitFile(
    LocalFile file,
    EntityKind owner,
  ) async => result;
}

void main() {
  test('sorts a scanned code by what it pays', () {
    expect(
      classifyScannedCode(' $sampleScannedCode '),
      const ScannedCode(kind: ScannedKind.pix, value: sampleScannedCode),
    );
    const barcode = '23799876000001199033812860000000000000000400';
    expect(
      classifyScannedCode(barcode),
      const ScannedCode(kind: ScannedKind.boleto, value: barcode),
    );
    expect(
      classifyScannedCode('84670000001-2 34567890123.4567890123456789012345'),
      isA<ScannedCode>().having((c) => c.kind, 'kind', ScannedKind.taxGuide),
    );
    expect(classifyScannedCode('https://exemplo.com'), isNull);
    expect(classifyScannedCode('1234'), isNull);
  });

  test('the fake takes files and codes, and gives a consent page', () async {
    final repository = FakeCaptureRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    final file = LocalFile(name: 'conta.pdf', bytes: Uint8List(2));

    expect(
      await repository.submitFile(
        LocalFile(name: 'vazio.pdf', bytes: Uint8List(0)),
        EntityKind.personal,
      ),
      isA<Err<CaptureOutcome>>(),
    );
    expect(
      await repository.submitFile(
        LocalFile(name: 'grande.pdf', bytes: Uint8List(maxUploadBytes + 1)),
        EntityKind.personal,
      ),
      const Ok<CaptureOutcome>(CaptureFileTooLarge(maxUploadBytes + 1)),
    );
    expect(
      await repository.submitFile(
        LocalFile(name: 'sem-codigo.pdf', bytes: Uint8List(2)),
        EntityKind.personal,
      ),
      const Ok<CaptureOutcome>(CaptureNothingFound()),
    );
    expect(
      await repository.submitFile(file, EntityKind.company),
      const Ok<CaptureOutcome>(BillCaptured(billId: 'captured-file-1')),
    );
    expect(
      await repository.capture(
        const BillDraft(
          owner: EntityKind.personal,
          channel: CaptureChannel.camera,
          pixCode: '000201',
        ),
      ),
      const Ok<CaptureOutcome>(BillCaptured(billId: 'captured-1')),
    );
    final url = await repository.mailboxAuthorizationUrl(EntityKind.company);

    expect(repository.submitted, [file]);
    expect(repository.drafts, hasLength(1));
    expect(url.toString(), contains('state=company'));
  });

  test('the fake asks for the amount of an open QR or a key', () async {
    final repository = FakeCaptureRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    final open = BillDraft(
      owner: EntityKind.personal,
      channel: CaptureChannel.camera,
      pixCode: testPixCode(amount: null),
    );
    const key = BillDraft(
      owner: EntityKind.personal,
      channel: CaptureChannel.manual,
      pixKey: 'contas@exemplo.com',
    );
    const asks = Ok<CaptureOutcome>(CaptureDetailsNeeded(amount: true));

    expect(await repository.capture(open), asks);
    expect(await repository.capture(key), asks);
    expect(
      await repository.capture(open.copyWith(amount: const Money(100))),
      isA<Ok<CaptureOutcome>>().having(
        (result) => result.value,
        'value',
        isA<BillCaptured>(),
      ),
    );
    expect(
      await repository.capture(
        BillDraft(
          owner: EntityKind.personal,
          channel: CaptureChannel.manual,
          paymentCode: '237',
          pixCode: testPixCode(amount: null),
        ),
      ),
      isA<Ok<CaptureOutcome>>().having(
        (result) => result.value,
        'value',
        isA<BillCaptured>(),
      ),
    );
  });

  testWidgets('the camera row scans a bill into Bills', (tester) async {
    final repository = FakeCaptureRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    final app = await pumpRoute(
      tester,
      AppRoutes.captureSources,
      overrides: [captureRepositoryProvider.overrideWithValue(repository)],
    );

    await tester.tap(find.byKey(CaptureSourcesScreen.scanKey));
    await settle(tester);
    expect(app.location, AppRoutes.scanBill);
    expect(find.text(l10n.scanHint), findsOneWidget);

    await tester.tap(find.byKey(fakeScannerKey));
    await settle(tester);

    expect(app.location, AppRoutes.bills);
    expect(find.text(l10n.scanPixRead), findsOneWidget);
    expect(repository.drafts.single.pixCode, sampleScannedCode);
    expect(repository.drafts.single.channel, CaptureChannel.camera);
    await waitForToast(tester);
  });

  testWidgets('an unknown code stays on the scanner', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.scanBill,
      overrides: [
        codeScannerProvider.overrideWithValue(fakeCodeScanner('olá')),
      ],
    );

    await tester.tap(find.byKey(fakeScannerKey));
    await settle(tester);

    expect(app.location, AppRoutes.scanBill);
    expect(find.text(l10n.scanUnknownCode), findsOneWidget);
    await waitForToast(tester);
  });

  for (final (code, message) in [
    ('23799876000001199033812860000000000000000400', 'boleto'),
    ('84670000001234567890123456789012345678901234', 'tax'),
  ]) {
    testWidgets('reads a $message barcode', (tester) async {
      await pumpRoute(
        tester,
        AppRoutes.scanBill,
        overrides: [
          codeScannerProvider.overrideWithValue(fakeCodeScanner(code)),
        ],
      );

      await tester.tap(find.byKey(fakeScannerKey));
      await settle(tester);

      expect(
        find.text(message == 'tax' ? l10n.scanTaxRead : l10n.scanBoletoRead),
        findsOneWidget,
      );
      await waitForToast(tester);
    });
  }

  testWidgets('a shared PDF opens its screen and goes to the company', (
    tester,
  ) async {
    final intake = FakeShareIntake();
    final repository = FakeCaptureRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        shareIntakeProvider.overrideWithValue(intake),
        captureRepositoryProvider.overrideWithValue(repository),
      ],
    );
    app.read(entityScopeProvider.notifier).select(EntityScope.company);

    intake.receive(LocalFile(name: 'das.pdf', bytes: Uint8List(2048)));
    await settle(tester);
    expect(app.location, AppRoutes.sharedFile);
    expect(find.text('das.pdf'), findsOneWidget);
    expect(find.text(l10n.fileSizeKb(2)), findsOneWidget);

    await tester.tap(find.text(l10n.entityPersonal));
    await settle(tester);
    await tester.tap(find.byKey(SharedFileScreen.sendKey));
    await settle(tester);

    expect(app.location, AppRoutes.bills);
    expect(find.text(l10n.sharedFileSentToast), findsOneWidget);
    expect(repository.submitted.single.name, 'das.pdf');
    await waitForToast(tester);
  });

  testWidgets('an empty shared file stays to be sent again', (tester) async {
    final intake = FakeShareIntake();
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [shareIntakeProvider.overrideWithValue(intake)],
    );

    intake.receive(LocalFile(name: 'foto.jpg', bytes: Uint8List(0)));
    await settle(tester);
    await tester.tap(find.byKey(SharedFileScreen.sendKey));
    await settle(tester);

    expect(app.location, AppRoutes.sharedFile);
    await waitForToast(tester);
  });

  testWidgets('the shared-file route without a file goes home', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.sharedFile);

    expect(app.location, AppRoutes.home);
  });

  group('a shared file the server cannot take', () {
    Future<ProviderContainer> share(
      WidgetTester tester,
      LocalFile file, {
      CaptureRepository? capture,
    }) => pumpRoute(
      tester,
      AppRoutes.sharedFile,
      extra: file,
      overrides: [
        captureRepositoryProvider.overrideWithValue(
          capture ??
              FakeCaptureRepository(
                FixedClock(testNow),
                latency: Duration.zero,
              ),
        ),
      ],
    );

    String tooLarge(String size) =>
        l10n.sharedFileTooLarge(l10n.fileSizeMb(size), l10n.fileSizeMb('3,3'));

    testWidgets('a PDF over the cap is refused before sending', (tester) async {
      final app = await share(
        tester,
        LocalFile(name: 'conta.pdf', bytes: Uint8List(4200000)),
      );

      expect(find.text(tooLarge('4,2')), findsOneWidget);
      await tester.tap(find.byKey(SharedFileScreen.sendKey));
      await settle(tester);
      expect(app.location, AppRoutes.sharedFile);

      await tester.tap(find.byKey(SharedFileScreen.pasteKey));
      await settle(tester);
      expect(app.location, AppRoutes.pasteCode);
    });

    testWidgets('a photo that still does not fit says so after sending', (
      tester,
    ) async {
      await share(
        tester,
        LocalFile(name: 'foto.jpg', bytes: Uint8List(maxUploadBytes + 1)),
      );
      expect(find.byKey(SharedFileScreen.pasteKey), findsNothing);

      await tester.tap(find.byKey(SharedFileScreen.sendKey));
      await settle(tester);

      expect(find.text(tooLarge('3,3')), findsOneWidget);
    });

    testWidgets('a file without a code points to pasting it', (tester) async {
      await share(
        tester,
        LocalFile(name: 'sem-codigo.pdf', bytes: Uint8List(10)),
      );

      await tester.tap(find.byKey(SharedFileScreen.sendKey));
      await settle(tester);

      expect(find.text(l10n.sharedFileNothingFound), findsOneWidget);
      expect(find.byKey(SharedFileScreen.pasteKey), findsOneWidget);
    });

    testWidgets('a duplicate goes to Bills and says so', (tester) async {
      final app = await share(
        tester,
        LocalFile(name: 'conta.pdf', bytes: Uint8List(10)),
        capture: _StubFiles(
          const Ok(BillCaptured(billId: 'b1', duplicate: true)),
        ),
      );

      await tester.tap(find.byKey(SharedFileScreen.sendKey));
      await settle(tester);

      expect(app.location, AppRoutes.bills);
      expect(find.text(l10n.captureDuplicateToast), findsOneWidget);
      await waitForToast(tester);
    });

    testWidgets('a failure stays and says why', (tester) async {
      final app = await share(
        tester,
        LocalFile(name: 'conta.pdf', bytes: Uint8List(10)),
        capture: _StubFiles(const Err(NetworkFailure())),
      );

      await tester.tap(find.byKey(SharedFileScreen.sendKey));
      await settle(tester);

      expect(app.location, AppRoutes.sharedFile);
      expect(find.text(l10n.errorNetwork), findsOneWidget);
      await waitForToast(tester);
    });
  });
}
