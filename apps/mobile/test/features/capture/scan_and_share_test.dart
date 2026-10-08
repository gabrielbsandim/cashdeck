import 'dart:typed_data';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:cashdeck/core/share/share_intake.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/data/fake_capture_repository.dart';
import 'package:cashdeck/features/capture/domain/scanned_code.dart';
import 'package:cashdeck/features/capture/presentation/capture_sources_screen.dart';
import 'package:cashdeck/features/capture/presentation/shared_file_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

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
      isA<Err<void>>(),
    );
    await repository.submitFile(file, EntityKind.company);
    await repository.submitCode(
      const ScannedCode(kind: ScannedKind.pix, value: '000201'),
      EntityKind.personal,
    );
    final url = await repository.mailboxAuthorizationUrl(EntityKind.company);

    expect(repository.submitted, [file]);
    expect(repository.codes, hasLength(1));
    expect(url.toString(), contains('state=company'));
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
    expect(repository.codes.single.kind, ScannedKind.pix);
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
}
