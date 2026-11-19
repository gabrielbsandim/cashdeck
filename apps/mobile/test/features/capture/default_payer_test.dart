import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:cashdeck/core/share/share_intake.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/data/fake_capture_repository.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/capture/presentation/paste_code_screen.dart';
import 'package:cashdeck/features/capture/presentation/scan_bill_screen.dart';
import 'package:cashdeck/features/capture/presentation/shared_file_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';

final class _RecordingFiles extends Fake implements CaptureRepository {
  final owners = <EntityKind>[];

  @override
  Future<Result<CaptureOutcome>> submitFile(
    LocalFile file,
    EntityKind owner, {
    Money? amount,
    CalendarDate? dueDate,
  }) async {
    owners.add(owner);
    return const Ok(BillCaptured(billId: 'file-1'));
  }
}

void main() {
  late FakeCaptureRepository repository;

  setUp(
    () => repository = FakeCaptureRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    ),
  );

  Future<ProviderContainer> scan(
    WidgetTester tester, {
    required String route,
    required EntityScope scope,
  }) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        captureRepositoryProvider.overrideWithValue(repository),
        codeScannerProvider.overrideWithValue(
          fakeCodeScanner(sampleScannedCode),
        ),
      ],
    );
    app.read(entityScopeProvider.notifier).select(scope);
    await tester.pump();
    app.router.go(route);
    await settle(tester);
    return app;
  }

  Future<void> read(WidgetTester tester) async {
    await tester.tap(find.byKey(fakeScannerKey));
    await settle(tester);
  }

  Future<void> pick(WidgetTester tester, EntityKind kind) async {
    await tester.tap(find.byKey(ScanBillScreen.ownerKey(kind)));
    await tester.pump();
  }

  Future<ProviderContainer> paste(
    WidgetTester tester,
    EntityScope scope,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': testPixCode()} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [captureRepositoryProvider.overrideWithValue(repository)],
    );
    app.read(entityScopeProvider.notifier).select(scope);
    await tester.pump();
    app.router.go(AppRoutes.pasteCode);
    await settle(tester);
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);
    return app;
  }

  final routes = [
    ('the scan screen', AppRoutes.scanBill),
    ('the pay-on-read scan', AppRoutes.sendPixScan),
  ];

  group('criterion 1: a scan defaults to personal', () {
    for (final (name, route) in routes) {
      testWidgets('$name with the switcher on the company', (tester) async {
        await scan(tester, route: route, scope: EntityScope.company);

        await read(tester);

        expect(repository.drafts.single.owner, EntityKind.personal);
        await waitForToast(tester);
      });
    }
  });

  group('criterion 2: the scan screen offers PF and PJ', () {
    for (final (name, route) in routes) {
      testWidgets('$name captures the company when PJ is tapped', (
        tester,
      ) async {
        await scan(tester, route: route, scope: EntityScope.personal);

        await pick(tester, EntityKind.company);
        await read(tester);

        expect(repository.drafts.single.owner, EntityKind.company);
        await waitForToast(tester);
      });

      testWidgets('$name reads the segment at capture time', (tester) async {
        await scan(tester, route: route, scope: EntityScope.company);

        await pick(tester, EntityKind.company);
        await pick(tester, EntityKind.personal);
        await read(tester);

        expect(repository.drafts.single.owner, EntityKind.personal);
        await waitForToast(tester);
      });
    }
  });

  group('criterion 3: paste and shared file default to personal', () {
    testWidgets('paste code with the switcher on the company', (tester) async {
      await paste(tester, EntityScope.company);

      expect(repository.drafts.single.owner, EntityKind.personal);
      await waitForToast(tester);
    });

    testWidgets('shared file with the switcher on the company', (tester) async {
      final files = _RecordingFiles();
      final app = await pumpRoute(
        tester,
        AppRoutes.home,
        overrides: [
          shareIntakeProvider.overrideWithValue(FakeShareIntake()),
          captureRepositoryProvider.overrideWithValue(files),
        ],
      );
      app.read(entityScopeProvider.notifier).select(EntityScope.company);
      await tester.pump();
      app.router.go(
        AppRoutes.sharedFile,
        extra: LocalFile(name: 'conta.pdf', bytes: Uint8List(10)),
      );
      await settle(tester);

      await tester.tap(find.byKey(SharedFileScreen.sendKey));
      await settle(tester);

      expect(files.owners, [EntityKind.personal]);
      await waitForToast(tester);
    });
  });

  group('criterion 6: the switcher follows the captured bill', () {
    testWidgets('a personal scan from the company switcher moves to personal', (
      tester,
    ) async {
      final app = await scan(
        tester,
        route: AppRoutes.scanBill,
        scope: EntityScope.company,
      );

      await read(tester);

      expect(app.read(entityScopeProvider), EntityScope.personal);
      await waitForToast(tester);
    });

    testWidgets('a company scan from the personal switcher moves to company', (
      tester,
    ) async {
      final app = await scan(
        tester,
        route: AppRoutes.scanBill,
        scope: EntityScope.personal,
      );

      await pick(tester, EntityKind.company);
      await read(tester);

      expect(app.read(entityScopeProvider), EntityScope.company);
      await waitForToast(tester);
    });

    testWidgets('the consolidated switcher stays consolidated', (tester) async {
      final app = await scan(
        tester,
        route: AppRoutes.scanBill,
        scope: EntityScope.consolidated,
      );

      await read(tester);

      expect(app.read(entityScopeProvider), EntityScope.consolidated);
      await waitForToast(tester);
    });

    testWidgets('a pay-on-read scan leaves the switcher alone', (tester) async {
      final app = await scan(
        tester,
        route: AppRoutes.sendPixScan,
        scope: EntityScope.company,
      );

      await read(tester);

      expect(app.read(entityScopeProvider), EntityScope.company);
    });

    testWidgets('a pasted code moves the switcher to personal', (tester) async {
      final app = await paste(tester, EntityScope.company);

      expect(app.read(entityScopeProvider), EntityScope.personal);
      await waitForToast(tester);
    });

    testWidgets('a pasted code keeps the consolidated switcher', (
      tester,
    ) async {
      final app = await paste(tester, EntityScope.consolidated);

      expect(app.read(entityScopeProvider), EntityScope.consolidated);
      await waitForToast(tester);
    });
  });
}
