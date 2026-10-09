import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/payroll/data/fake_payroll_repository.dart';
import 'package:cashdeck/features/payroll/domain/payroll.dart';
import 'package:cashdeck/features/payroll/payroll_providers.dart';
import 'package:cashdeck/features/payroll/presentation/payroll_input_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _NoRevenue implements PayrollRepository {
  bool fail = true;

  static const _month = PayrollMonth(
    month: CalendarDate(2026, 10, 1),
    proLabore: Money(100),
    salaries: Money(0),
    fgts: Money(0),
  );

  @override
  Future<Result<PayrollSheet>> sheet() async {
    if (fail) return const Err(NetworkFailure());
    return const Ok(
      PayrollSheet(current: _month, history: [], revenue12: Money(0)),
    );
  }

  @override
  Future<Result<PayrollSheet>> save(PayrollMonth month) async =>
      const Err(NetworkFailure());

  @override
  Future<Result<PayrollSheet>> declareAnnex(SimplesAnnex? annex) async {
    if (annex == SimplesAnnex.v) return const Err(NetworkFailure());
    return Ok(
      PayrollSheet(
        current: _month,
        history: const [],
        revenue12: const Money(0),
        declaredAnnex: annex,
      ),
    );
  }
}

void main() {
  final repository = FakePayrollRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );

  test('Fator R puts the company in Anexo III from 28%', () async {
    final sheet = (await repository.sheet() as Ok<PayrollSheet>).value;
    final fator = FatorR.of(
      current: sheet.current,
      history: sheet.history,
      revenue12: sheet.revenue12,
    );

    expect(sheet.current.month, const CalendarDate(2026, 10, 1));
    expect(sheet.history.last.month, const CalendarDate(2025, 11, 1));
    expect(sheet.current.total, const Money(735_000));
    expect(fator.payroll12, const Money(8_820_000));
    expect(fator.ratio, closeTo(0.307, 0.001));
    expect(fator.annex, SimplesAnnex.iii);
    expect(
      const FatorR(payroll12: Money(27), revenue12: Money(100)).annex,
      SimplesAnnex.v,
    );
    expect(const FatorR(payroll12: Money(1), revenue12: Money(0)).ratio, 0);
    expect(fator.props, hasLength(2));
    expect(sheet.props, hasLength(4));
    expect(sheet.fullYear, isTrue);
    expect(sheet.annexOf(fator), SimplesAnnex.iii);
    expect(sheet.current.props, hasLength(4));
  });

  test('the fake keeps the saved month', () async {
    final sheet = (await repository.sheet() as Ok<PayrollSheet>).value;
    final edited = sheet.current.copyWith(
      proLabore: const Money(1),
      salaries: const Money(2),
      fgts: const Money(3),
    );

    final saved = (await repository.save(edited) as Ok<PayrollSheet>).value;

    expect(saved.current.total, const Money(6));
    expect(
      (await repository.sheet() as Ok<PayrollSheet>).value.current,
      edited,
    );
    expect(edited.copyWith(), edited);

    final declared = (await repository.declareAnnex(
      SimplesAnnex.v,
    ) as Ok<PayrollSheet>).value;
    expect(declared.declaredAnnex, SimplesAnnex.v);
    const short = PayrollSheet(
      current: PayrollMonth(
        month: CalendarDate(2026, 10, 1),
        proLabore: Money(0),
        salaries: Money(0),
        fgts: Money(0),
      ),
      history: [],
      revenue12: Money(100),
      declaredAnnex: SimplesAnnex.iii,
    );
    const nothing = FatorR(payroll12: Money(0), revenue12: Money(100));
    expect(short.annexOf(nothing), SimplesAnnex.iii);
    await repository.declareAnnex(null);
  });

  test('the provider reads the fake', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(payrollRepositoryProvider),
      isA<FakePayrollRepository>(),
    );
  });

  testWidgets('edits the month, updates Fator R and saves', (tester) async {
    await pumpRoute(tester, AppRoutes.payroll);
    expect(find.text(l10n.payrollTitle('outubro')), findsOneWidget);
    expect(find.text(l10n.fatorR('30,7')), findsOneWidget);
    expect(find.text(l10n.annexIii), findsOneWidget);
    expect(find.text('Setembro'), findsOneWidget);
    expect(find.byKey(PayrollInputScreen.annexIiiKey), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(PayrollInputScreen.proLaboreKey),
        matching: find.byType(TextField),
      ),
      '0',
    );
    await settle(tester);
    expect(find.text(l10n.fatorR('28,6')), findsOneWidget);
    expect(
      find.text(MoneyFormat.format(const Money(8_220_000))),
      findsOneWidget,
    );

    await tester.tap(find.byKey(PayrollInputScreen.saveKey));
    await settle(tester);
    expect(find.text(l10n.payrollSavedToast), findsOneWidget);
  });

  testWidgets('no revenue falls in Anexo V, and failures say why', (
    tester,
  ) async {
    final flaky = _NoRevenue();
    await pumpRoute(
      tester,
      AppRoutes.payroll,
      overrides: [payrollRepositoryProvider.overrideWithValue(flaky)],
    );
    expect(find.text(l10n.payrollMenu), findsOneWidget);
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    flaky.fail = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    expect(find.text(l10n.annexV), findsNWidgets(2));
    expect(find.text(l10n.payrollAnnexTitle), findsOneWidget);

    await tester.tap(find.byKey(PayrollInputScreen.annexIiiKey));
    await settle(tester);
    expect(find.text(l10n.payrollAnnexSaved), findsOneWidget);
    expect(find.text(l10n.annexIii), findsNWidgets(2));

    await tester.tap(find.text(l10n.annexV));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
    expect(find.text(l10n.annexIii), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(PayrollInputScreen.saveKey));
    await tester.tap(find.byKey(PayrollInputScreen.saveKey));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });
}
