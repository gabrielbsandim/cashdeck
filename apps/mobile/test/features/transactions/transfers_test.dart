import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/transactions/data/fake_transfers_repository.dart';
import 'package:cashdeck/features/transactions/domain/internal_transfer.dart';
import 'package:cashdeck/features/transactions/presentation/transfer_detail_screen.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';
import '../../support/builders.dart';
import '../../support/pump_app.dart';

final class _Flaky implements TransfersRepository {
  final _inner = FakeTransfersRepository(
    FixedClock(testNow),
    latency: Duration.zero,
  );
  bool fail = true;

  @override
  Future<Result<TransferDetail>> transfer(String id) async {
    if (fail) return const Err(NetworkFailure());
    return await _inner.transfer(id);
  }
}

void main() {
  test('a distribution is neutral and a pro-labore is counted', () async {
    final repository = FakeTransfersRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );
    TransferDetail valueOf(Result<TransferDetail> result) =>
        (result as Ok<TransferDetail>).value;

    final distribution = valueOf(
      await repository.transfer('transfer-distribution'),
    );
    final proLabore = valueOf(await repository.transfer('transfer-prolabore'));

    expect(distribution.neutral, isTrue);
    expect(distribution.at, DateTime.utc(2026, 10, 6, 13, 15));
    expect(distribution.document, 'ata-distribuicao-set.pdf');
    expect(proLabore.neutral, isFalse);
    expect(proLabore.amount, const Money(780_000));
    expect(proLabore.document, isNull);
    expect(distribution.props, hasLength(8));
    expect(distribution.from.props, hasLength(3));
    expect(
      await repository.transfer('none'),
      const Err<TransferDetail>(NotFoundFailure()),
    );
  });

  test('the provider reads the fake', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(transfersRepositoryProvider),
      isA<FakeTransfersRepository>(),
    );
  });

  testWidgets('a distribution shows each view as neutral and its minutes', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.transfer('transfer-distribution'));

    expect(find.text(l10n.transferProfitDistribution), findsNWidgets(2));
    expect(find.textContaining('10:15'), findsOneWidget);
    expect(find.text('Estúdio Vento Sul'), findsOneWidget);
    expect(find.text(l10n.countsCompanyNeutral), findsOneWidget);
    expect(find.text(l10n.countsPersonalNeutral), findsOneWidget);
    expect(find.text(l10n.neutralBadge), findsNWidgets(3));

    await tester.tap(find.byKey(TransferDetailScreen.documentKey));
    await settle(tester);
    expect(find.text(l10n.shareSoon), findsOneWidget);
  });

  testWidgets('a pro-labore counts on both sides', (tester) async {
    await pumpRoute(tester, AppRoutes.transfer('transfer-prolabore'));

    expect(find.text(l10n.countsCompanyExpense), findsOneWidget);
    expect(find.text(l10n.countsPersonalIncome), findsOneWidget);
    expect(find.text(l10n.countedBadge), findsNWidgets(3));
    expect(find.byKey(TransferDetailScreen.documentKey), findsNothing);
  });

  testWidgets('a failed load can be retried', (tester) async {
    final repository = _Flaky();
    await pumpRoute(
      tester,
      AppRoutes.transfer('transfer-prolabore'),
      overrides: [transfersRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository.fail = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    expect(find.text(l10n.transferProLabore), findsNWidgets(2));
  });
}
