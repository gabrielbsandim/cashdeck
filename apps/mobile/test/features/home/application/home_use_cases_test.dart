import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/application/home_use_cases.dart';
import 'package:cashdeck/features/home/data/fake_home_repository.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/home_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';

void main() {
  late FakeHomeRepository repository;

  setUp(
    () => repository = FakeHomeRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    ),
  );

  T valueOf<T>(Result<T> result) => (result as Ok<T>).value;

  test('loads the summary of each scope', () async {
    final load = LoadHome(repository);

    expect(valueOf(await load(EntityScope.personal)), isA<PersonalSummary>());
    expect(valueOf(await load(EntityScope.company)), isA<CompanySummary>());
    expect(
      valueOf(await load(EntityScope.consolidated)),
      isA<ConsolidatedSummary>(),
    );
  });

  test('the personal forecast dips before the salary arrives', () async {
    final personal = valueOf(await repository.personal());

    expect(personal.forecast.lowest, const Money(1_048_336));
    expect(personal.forecast.lowestDate, const CalendarDate(2026, 11, 4));
    expect(personal.forecast.last, const Money(1_802_836));
    expect(personal.alerts.first, isA<AssistedPaymentAlert>());
    expect(
      (personal.alerts.first as AssistedPaymentAlert).reason,
      'Acima do limite por pagamento, sem confirmação no app',
    );
  });

  test('approving a draft or issuing an invoice clears it once', () async {
    final approve = ApproveInvoiceDraft(repository);
    final issue = IssueInvoiceForReceipt(repository);

    expect(valueOf(await approve('draft-pomar')).drafts, isEmpty);
    expect(valueOf(await issue('receipt-pix-lia')).unbilled, isEmpty);
    expect(
      await approve('draft-pomar'),
      const Err<CompanySummary>(NotFoundFailure()),
    );
    expect(
      await issue('receipt-pix-lia'),
      const Err<CompanySummary>(NotFoundFailure()),
    );
  });

  test('both backends read the fake summary', () {
    final container = ProviderContainer(
      overrides: [clockProvider.overrideWithValue(FixedClock(testNow))],
    );
    addTearDown(container.dispose);

    expect(container.read(homeRepositoryProvider), isA<FakeHomeRepository>());
    expect(container.read(loadHomeProvider), isA<LoadHome>());
    expect(
      container.read(approveInvoiceDraftProvider),
      isA<ApproveInvoiceDraft>(),
    );
    expect(
      container.read(issueInvoiceForReceiptProvider),
      isA<IssueInvoiceForReceipt>(),
    );
  });
}
