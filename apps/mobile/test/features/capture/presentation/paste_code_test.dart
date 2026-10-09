import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:cashdeck/core/share/share_intake.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/bills/presentation/bills_screen.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/data/fake_capture_repository.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/capture/presentation/capture_details_sheet.dart';
import 'package:cashdeck/features/capture/presentation/paste_code_screen.dart';
import 'package:cashdeck/features/capture/presentation/scan_bill_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/pump_app.dart';

final class _StubCapture extends Fake implements CaptureRepository {
  new(this.result);

  final Result<CaptureOutcome> result;

  @override
  Future<Result<CaptureOutcome>> capture(BillDraft draft) async => result;
}

void main() {
  late FakeCaptureRepository repository;

  setUp(
    () => repository = FakeCaptureRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    ),
  );

  void clipboard(WidgetTester tester, String? text) {
    final messenger = tester.binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method != 'Clipboard.getData') return null;
        return text == null ? null : {'text': text};
      });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
  }

  Future<ProviderContainer> open(
    WidgetTester tester, {
    String? onClipboard,
    CaptureRepository? capture,
  }) {
    clipboard(tester, onClipboard);
    return pumpRoute(
      tester,
      AppRoutes.pasteCode,
      overrides: [
        captureRepositoryProvider.overrideWithValue(capture ?? repository),
      ],
    );
  }

  Finder field(Key key) =>
      find.descendant(of: find.byKey(key), matching: find.byType(TextField));

  testWidgets('opens with the Pix already on the clipboard and saves it', (
    tester,
  ) async {
    final payload = testPixCode();
    final app = await open(tester, onClipboard: payload);

    expect(find.text(payload), findsOneWidget);
    expect(find.text(l10n.pasteCodeFromClipboard), findsOneWidget);
    expect(find.text(l10n.pasteKindPix), findsOneWidget);
    expect(find.text(l10n.pixInfoTitle), findsOneWidget);
    expect(find.text('CURITIBA'), findsOneWidget);
    expect(find.text(MoneyFormat.format(const Money(11990))), findsOneWidget);
    expect(find.text('loja@exemplo.com'), findsOneWidget);
    expect(find.byKey(PasteCodeScreen.amountKey), findsNothing);
    expect(find.text(l10n.captureDueDateFromCode), findsOneWidget);

    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);

    expect(app.location, AppRoutes.bills);
    expect(find.text(l10n.captureSavedToast), findsOneWidget);
    final draft = repository.drafts.single;
    expect(draft.pixCode, payload);
    expect(draft.payee, 'LOJA EXEMPLO');
    expect(draft.channel, CaptureChannel.manual);
    expect(draft.dueDate, isNull);
    await waitForToast(tester);
  });

  testWidgets('a clipboard without a code is pasted only on request', (
    tester,
  ) async {
    final app = await open(tester, onClipboard: 'olá, tudo bem?');

    expect(find.text(l10n.pasteCodeUnknown), findsNothing);
    await tester.tap(find.byKey(PasteCodeScreen.clipboardKey));
    await settle(tester);

    expect(find.text(l10n.pasteCodeUnknown), findsOneWidget);
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);
    expect(app.location, AppRoutes.pasteCode);
    expect(repository.drafts, isEmpty);
  });

  testWidgets('an empty clipboard leaves the field alone', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(PasteCodeScreen.clipboardKey));
    await settle(tester);

    expect(find.text(l10n.pasteCodeUnknown), findsNothing);
    expect(find.text(l10n.pasteCodeFromClipboard), findsNothing);
  });

  testWidgets('a broken Pix code says the checksum fails', (tester) async {
    final payload = testPixCode();
    await open(tester);

    await tester.enterText(
      field(PasteCodeScreen.codeKey),
      '${payload.substring(0, payload.length - 4)}0000',
    );
    await tester.pump();

    expect(find.text(l10n.pasteCodeBadPix), findsOneWidget);
  });

  testWidgets('a Pix key needs the amount, for today, on the company', (
    tester,
  ) async {
    final app = await open(tester);

    await tester.enterText(field(PasteCodeScreen.codeKey), '(11) 98765-4321');
    await tester.pump();
    expect(find.text(l10n.pasteKindPixKey(l10n.pixKeyPhone)), findsOneWidget);
    expect(find.text(l10n.captureAmountRequired), findsOneWidget);
    expect(find.text(testToday.display), findsOneWidget);

    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);
    expect(app.location, AppRoutes.pasteCode);

    await tester.enterText(field(PasteCodeScreen.amountKey), '5000');
    await tester.enterText(field(PasteCodeScreen.payeeKey), 'Diarista');
    await tester.tap(find.text(l10n.entityCompany));
    await tester.pump();
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);

    expect(app.location, AppRoutes.bills);
    final draft = repository.drafts.single;
    expect(draft.pixKey, '+5511987654321');
    expect(draft.amount, const Money(5000));
    expect(draft.dueDate, testToday);
    expect(draft.payee, 'Diarista');
    expect(draft.owner, EntityKind.company);
    await waitForToast(tester);
  });

  testWidgets('a boleto line takes its Pix code too', (tester) async {
    final payload = testPixCode();
    await open(tester);

    await tester.enterText(field(PasteCodeScreen.codeKey), testBoletoLine);
    await tester.pump();
    expect(find.text(l10n.pasteKindBoleto), findsOneWidget);
    expect(find.text(l10n.captureAmountFromCode), findsOneWidget);

    await tester.enterText(field(PasteCodeScreen.bolepixKey), '000201 errado');
    await tester.pump();
    expect(find.text(l10n.pasteCodeBadPix), findsOneWidget);
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);
    expect(repository.drafts, isEmpty);

    await tester.enterText(field(PasteCodeScreen.bolepixKey), payload);
    await tester.pump();
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);

    final draft = repository.drafts.single;
    expect(draft.paymentCode, hasLength(47));
    expect(draft.pixCode, payload);
    expect(draft.amount, isNull);
    await waitForToast(tester);
  });

  testWidgets('a guide line reads as one', (tester) async {
    await open(tester);

    await tester.enterText(field(PasteCodeScreen.codeKey), testGuideLine);
    await tester.pump();

    expect(find.text(l10n.pasteKindTaxGuide), findsOneWidget);
  });

  testWidgets('an open QR asks the amount on the screen', (tester) async {
    await open(tester, onClipboard: testPixCode(amount: null));

    expect(find.text(l10n.pixInfoAmountOpen), findsOneWidget);
    await tester.enterText(field(PasteCodeScreen.amountKey), '1234');
    await tester.pump();
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);

    expect(repository.drafts.single.amount, const Money(1234));
    expect(repository.drafts.single.dueDate, testToday);
    await waitForToast(tester);
  });

  testWidgets('shared text opens here with the code inside it', (tester) async {
    final payload = testPixCode();
    final intake = FakeShareIntake();
    clipboard(tester, null);
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        shareIntakeProvider.overrideWithValue(intake),
        captureRepositoryProvider.overrideWithValue(repository),
      ],
    );

    intake.receiveText('Pague com Pix: $payload Obrigado!');
    await settle(tester);
    expect(app.location, AppRoutes.pasteCode);
    expect(find.text(payload), findsOneWidget);

    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);

    expect(repository.drafts.single.channel, CaptureChannel.share);
    await waitForToast(tester);
  });

  testWidgets('shared text that is not a code stays to be fixed', (
    tester,
  ) async {
    final intake = FakeShareIntake();
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [shareIntakeProvider.overrideWithValue(intake)],
    );

    intake.receiveText('  lembrete: pagar a escola  ');
    await settle(tester);

    expect(app.location, AppRoutes.pasteCode);
    expect(find.text('lembrete: pagar a escola'), findsOneWidget);
    expect(find.text(l10n.pasteCodeUnknown), findsOneWidget);
  });

  testWidgets('a duplicate says so', (tester) async {
    final payload = testPixCode();
    await open(
      tester,
      onClipboard: payload,
      capture: _StubCapture(
        const Ok(BillCaptured(billId: 'b1', duplicate: true)),
      ),
    );
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);

    expect(find.text(l10n.captureDuplicateToast), findsOneWidget);
    await waitForToast(tester);
  });

  testWidgets('a failed save stays and says why', (tester) async {
    final app = await open(
      tester,
      onClipboard: testPixCode(),
      capture: _StubCapture(const Err(NetworkFailure())),
    );
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);

    expect(app.location, AppRoutes.pasteCode);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    await waitForToast(tester);
  });

  testWidgets('an outcome with nothing to show stays put', (tester) async {
    final app = await open(
      tester,
      onClipboard: testPixCode(),
      capture: _StubCapture(const Ok(CaptureNothingFound())),
    );
    await tester.tap(find.byKey(PasteCodeScreen.saveKey));
    await settle(tester);

    expect(app.location, AppRoutes.pasteCode);
  });

  testWidgets('the Bills button and the scanner open it', (tester) async {
    clipboard(tester, null);
    final app = await pumpRoute(tester, AppRoutes.bills);

    await tester.tap(find.byKey(BillsScreen.pasteKey));
    await settle(tester);
    expect(app.location, AppRoutes.pasteCode);

    app.router.go(AppRoutes.scanBill);
    await settle(tester);
    await tester.tap(find.byKey(ScanBillScreen.pasteKey));
    await settle(tester);
    expect(app.location, AppRoutes.pasteCode);
  });

  group('after a scan without an amount', () {
    Future<ProviderContainer> scan(WidgetTester tester) async {
      final app = await pumpRoute(
        tester,
        AppRoutes.scanBill,
        overrides: [
          captureRepositoryProvider.overrideWithValue(repository),
          codeScannerProvider.overrideWithValue(
            fakeCodeScanner(testPixCode(amount: null)),
          ),
        ],
      );
      await tester.tap(find.byKey(fakeScannerKey));
      await settle(tester);
      return app;
    }

    testWidgets('the sheet asks amount and date, then sends again', (
      tester,
    ) async {
      final app = await scan(tester);
      expect(find.text(l10n.captureDetailsTitle), findsOneWidget);
      expect(find.text(testToday.display), findsOneWidget);

      await tester.tap(find.byKey(CaptureDetailsSheet.submitKey));
      await settle(tester);
      expect(repository.drafts, isEmpty);

      await tester.enterText(field(CaptureDetailsSheet.amountKey), '4590');
      await tester.tap(find.byKey(DueDateField.changeKey));
      await settle(tester);
      await tester.tap(find.text('20'));
      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(DatePickerDialog)),
          ).okButtonLabel,
        ),
      );
      await settle(tester);
      expect(
        find.text(const CalendarDate(2026, 10, 20).display),
        findsOneWidget,
      );
      await tester.tap(find.byKey(CaptureDetailsSheet.submitKey));
      await settle(tester);

      expect(app.location, AppRoutes.bills);
      final draft = repository.drafts.single;
      expect(draft.amount, const Money(4590));
      expect(draft.dueDate, const CalendarDate(2026, 10, 20));
      await waitForToast(tester);
    });

    testWidgets('a cancelled picker keeps the date; closing the sheet stays', (
      tester,
    ) async {
      final app = await scan(tester);

      await tester.tap(find.byKey(DueDateField.changeKey));
      await settle(tester);
      await tester.tap(
        find.text(
          MaterialLocalizations.of(
            tester.element(find.byType(DatePickerDialog)),
          ).cancelButtonLabel,
        ),
      );
      await settle(tester);
      expect(find.text(testToday.display), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await settle(tester);

      expect(app.location, AppRoutes.scanBill);
      expect(repository.drafts, isEmpty);
    });
  });

  testWidgets('a missing due date asks only the date', (tester) async {
    CaptureDetails? answer;
    await tester.pumpApp(
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => answer = await showCaptureDetailsSheet(
            context,
            askAmount: false,
            today: testToday,
          ),
          child: const Text('abrir'),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.captureDetailsDueTitle), findsOneWidget);
    expect(find.byKey(CaptureDetailsSheet.amountKey), findsNothing);
    await tester.tap(find.byKey(CaptureDetailsSheet.submitKey));
    await tester.pumpAndSettle();

    expect(answer, (amount: null, dueDate: testToday));
  });
}
