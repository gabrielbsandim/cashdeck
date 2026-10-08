import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/invoices/data/fake_issuer_repository.dart';
import 'package:cashdeck/features/invoices/domain/issuer_setup.dart';
import 'package:cashdeck/features/invoices/invoices_providers.dart';
import 'package:cashdeck/features/invoices/presentation/invoice_issuer_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _Flaky implements IssuerRepository {
  final _inner = FakeIssuerRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );
  bool failSetup = true;

  @override
  Future<Result<IssuerSetup>> setup() async {
    if (failSetup) return const Err(NetworkFailure());
    return await _inner.setup();
  }

  @override
  Future<Result<List<ServiceCode>>> serviceCodes() => _inner.serviceCodes();

  @override
  Future<Result<IssuerSetup>> save(IssuerSetup setup) => _inner.save(setup);

  @override
  Future<Result<TestEmission>> emitTest(IssuerSetup setup) async =>
      const Err(NetworkFailure());
}

void main() {
  test('a certificate is urgent from 45 days before it expires', () {
    expect(
      certificateStateOf(testToday.addDays(46), testToday),
      CertificateState.valid,
    );
    expect(
      certificateStateOf(testToday.addDays(45), testToday),
      CertificateState.expiringSoon,
    );
    expect(
      certificateStateOf(testToday, testToday),
      CertificateState.expiringSoon,
    );
    expect(
      certificateStateOf(testToday.addDays(-1), testToday),
      CertificateState.expired,
    );
  });

  test(
    'the fake keeps what is saved and refuses a blank registration',
    () async {
      final repository = FakeIssuerRepository(
        FixedClock(testNow),
        latency: Duration.zero,
      );
      final setup = (await repository.setup() as Ok<IssuerSetup>).value;

      expect(setup.certificateExpiresOn, const CalendarDate(2026, 11, 14));
      expect(setup.props, hasLength(6));
      expect(FakeIssuerRepository.codes.first.props, [
        '1.07',
        'Suporte técnico em TI',
      ]);
      expect(
        await repository.serviceCodes(),
        const Ok(FakeIssuerRepository.codes),
      );
      expect(
        await repository.save(setup.copyWith(municipalRegistration: ' ')),
        const Err<IssuerSetup>(ValidationFailure('municipalRegistration')),
      );
      final municipal = setup.copyWith(
        kind: IssuerKind.municipal,
        serviceCode: FakeIssuerRepository.codes.last,
      );
      expect(await repository.save(municipal), Ok(municipal));
      expect(await repository.setup(), Ok(municipal));
      final emission =
          (await repository.emitTest(municipal) as Ok<TestEmission>).value;
      expect(emission.props, [
        '2026-000184',
        const Duration(milliseconds: 1800),
      ]);
    },
  );

  test('the provider reads the fake', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(issuerRepositoryProvider),
      isA<FakeIssuerRepository>(),
    );
  });

  testWidgets('sets the issuer, tests an emission and saves', (tester) async {
    await pumpRoute(tester, AppRoutes.invoiceIssuer);
    expect(
      find.text(l10n.certificateExpiresIn(37, '14/11/2026')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(InvoiceIssuerSetupScreen.uploadKey));
    await settle(tester);
    expect(find.text(l10n.filePickerSoon), findsOneWidget);
    await waitForToast(tester);
    await tester.tap(find.byKey(InvoiceIssuerSetupScreen.remindKey));
    await settle(tester);
    expect(find.byKey(InvoiceIssuerSetupScreen.uploadKey), findsNothing);

    await tester.tap(
      find.byKey(InvoiceIssuerSetupScreen.kindKey(IssuerKind.municipal)),
    );
    await settle(tester);
    await tester.tap(find.text(l10n.issuerNational));
    await settle(tester);

    await tester.tap(find.byKey(InvoiceIssuerSetupScreen.serviceKey));
    await settle(tester);
    await tester.tap(find.text('17.01 · Assessoria ou consultoria').last);
    await settle(tester);
    expect(find.text('17.01 · Assessoria ou consultoria'), findsOneWidget);

    await tester.tap(find.byKey(InvoiceIssuerSetupScreen.testKey));
    await settle(tester);
    expect(
      find.text(l10n.testEmissionResult('2026-000184', '1,8')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(InvoiceIssuerSetupScreen.saveKey));
    await settle(tester);
    expect(find.text(l10n.issuerSavedToast), findsOneWidget);
    await waitForToast(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byKey(InvoiceIssuerSetupScreen.saveKey));
    await settle(tester);
    expect(find.text('municipalRegistration'), findsOneWidget);
  });

  testWidgets('a valid certificate asks for nothing', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.invoiceIssuer,
      overrides: [
        issuerRepositoryProvider.overrideWithValue(
          FakeIssuerRepository(
            FixedClock(testNow.add(const Duration(days: 20))),
            latency: Duration.zero,
          ),
        ),
      ],
    );

    expect(find.text(l10n.validUntil('04/12/2026')), findsOneWidget);
    expect(find.byKey(InvoiceIssuerSetupScreen.uploadKey), findsNothing);
  });

  testWidgets('an expired certificate is said so', (tester) async {
    await pumpRoute(
      tester,
      AppRoutes.invoiceIssuer,
      overrides: [
        issuerRepositoryProvider.overrideWithValue(
          FakeIssuerRepository(
            FixedClock(testNow.subtract(const Duration(days: 60))),
            latency: Duration.zero,
          ),
        ),
      ],
    );

    expect(find.text(l10n.certificateExpired('15/09/2026')), findsOneWidget);
    expect(find.byKey(InvoiceIssuerSetupScreen.uploadKey), findsOneWidget);
  });

  testWidgets('a failed load or test emission says why', (tester) async {
    final repository = _Flaky();
    await pumpRoute(
      tester,
      AppRoutes.invoiceIssuer,
      overrides: [issuerRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository.failSetup = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    await tester.tap(find.byKey(InvoiceIssuerSetupScreen.testKey));
    await settle(tester);

    expect(find.textContaining('2026-000184'), findsNothing);
  });
}
