import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/accountant_export/accountant_export_providers.dart';
import 'package:cashdeck/features/accountant_export/data/fake_accountant_export_repository.dart';
import 'package:cashdeck/features/accountant_export/domain/accountant_export.dart';
import 'package:cashdeck/features/accountant_export/presentation/accountant_export_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _Flaky implements AccountantExportRepository {
  final _inner = FakeAccountantExportRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );
  bool failPlan = true;

  @override
  Future<Result<ExportPlan>> plan(ExportPeriod period) async {
    if (failPlan) return const Err(NetworkFailure());
    return await _inner.plan(period);
  }

  @override
  Future<Result<List<ExportRecord>>> history() => _inner.history();

  @override
  Future<Result<ExportRecord>> generate(
    ExportPeriod period,
    Set<ExportItemKind> items,
  ) async => const Err(NetworkFailure());
}

void main() {
  final defaults = {
    ExportItemKind.statements,
    ExportItemKind.invoices,
    ExportItemKind.taxGuides,
    ExportItemKind.expenses,
    ExportItemKind.payroll,
  };

  test('the plan sizes the selected documents per period', () async {
    final repository = FakeAccountantExportRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    ExportPlan planOf(Result<ExportPlan> result) =>
        (result as Ok<ExportPlan>).value;

    final month = planOf(await repository.plan(ExportPeriod.lastMonth));
    final quarter = planOf(await repository.plan(ExportPeriod.lastQuarter));
    final custom = planOf(await repository.plan(ExportPeriod.custom));

    expect(month.from, const CalendarDate(2026, 9, 1));
    expect(quarter.from, const CalendarDate(2026, 7, 1));
    expect(custom, month);
    expect(month.sizeOf(defaults), (214, 38_000_000));
    expect(quarter.sizeOf(defaults), (642, 114_000_000));
    expect(month.sizeOf({}), (0, 0));
    expect(month.items[4].count, '09/2026');
    expect(month.props, hasLength(2));
    expect(month.items.first.props, hasLength(5));
  });

  test('generating records the send and refuses an empty ZIP', () async {
    final repository = FakeAccountantExportRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );

    expect(
      await repository.generate(ExportPeriod.lastMonth, {}),
      const Err<ExportRecord>(ValidationFailure('items')),
    );
    final sent = await repository.generate(ExportPeriod.lastMonth, defaults);
    const record = ExportRecord(
      month: CalendarDate(2026, 9, 1),
      sentOn: testToday,
      to: FakeAccountantExportRepository.accountant,
    );
    expect(sent, const Ok(record));
    expect(record.props, hasLength(3));
    expect((await repository.history() as Ok<List<ExportRecord>>).value, [
      record,
      const ExportRecord(
        month: CalendarDate(2026, 8, 1),
        sentOn: CalendarDate(2026, 9, 5),
        to: FakeAccountantExportRepository.accountant,
      ),
    ]);
  });

  test('every item has a label and the provider reads the fake', () {
    for (final kind in ExportItemKind.values) {
      expect(exportItemLabel(l10n, kind), isNotEmpty);
    }
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(accountantExportRepositoryProvider),
      isA<FakeAccountantExportRepository>(),
    );
  });

  testWidgets('picks the period and contents, then sends the ZIP', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.accountantExport);
    expect(find.text(l10n.exportMonth('Setembro', '2026')), findsOneWidget);
    expect(find.text(l10n.exportZip(214, 38)), findsOneWidget);
    expect(find.text(l10n.exportMonth('Agosto', '2026')), findsOneWidget);

    await tester.tap(
      find.byKey(AccountantExportScreen.itemKey(ExportItemKind.reconciliation)),
    );
    await settle(tester);
    expect(find.text(l10n.exportZip(215, 38)), findsOneWidget);
    await tester.tap(
      find.byKey(AccountantExportScreen.itemKey(ExportItemKind.expenses)),
    );
    await settle(tester);
    expect(find.text(l10n.exportZip(25, 5)), findsOneWidget);

    await tester.tap(
      find.byKey(AccountantExportScreen.periodKey(ExportPeriod.lastQuarter)),
    );
    await settle(tester);
    expect(find.text(l10n.exportZip(642, 114)), findsOneWidget);

    await tester.tap(find.byKey(AccountantExportScreen.generateKey));
    await settle(tester);
    expect(find.text(l10n.exportSentToast), findsOneWidget);
    expect(
      find.text(
        l10n.exportSentLine('08/10', FakeAccountantExportRepository.accountant),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a failed plan or send says why', (tester) async {
    final repository = _Flaky();
    await pumpRoute(
      tester,
      AppRoutes.accountantExport,
      overrides: [
        accountantExportRepositoryProvider.overrideWithValue(repository),
      ],
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository.failPlan = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    await tester.tap(find.byKey(AccountantExportScreen.generateKey));
    await settle(tester);
    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });
}
