import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home_widget/application/refresh_home_widget.dart';
import 'package:cashdeck/features/home_widget/domain/widget_settings.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:cashdeck/features/home_widget/domain/widget_sources.dart';
import 'package:cashdeck/features/insights/domain/insights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/builders.dart';
import '../../../support/mocks.dart';
import '../home_widget_support.dart';

const _session = ServerCredentials(
  baseUrl: 'https://cashdeck.example.test',
  token: 'device-token',
);

void main() {
  late MockOutlookRepository outlook;
  late MockBillsRepository bills;
  late MockInsightsRepository insights;
  late FakeHomeWidgetPublisher publisher;
  late List<ServerCredentials> opened;
  late int closed;

  setUp(() {
    outlook = MockOutlookRepository();
    bills = MockBillsRepository();
    insights = MockInsightsRepository();
    publisher = FakeHomeWidgetPublisher();
    opened = [];
    closed = 0;
  });

  RefreshHomeWidget refresh({ServerCredentials? session = _session}) =>
      RefreshHomeWidget(
        credentials: InMemoryCredentialStore(session),
        open: (session) {
          opened.add(session);
          return WidgetSources(
            outlook: outlook,
            bills: bills,
            insights: insights,
            close: () => closed++,
          );
        },
        publisher: publisher,
        clock: FixedClock(testNow),
      );

  void answer({
    required Result<Object> free,
    required Result<Object> listing,
    required Result<Object> overview,
    EntityScope scope = EntityScope.personal,
    EntityKind? owner = EntityKind.personal,
  }) {
    when(() => outlook.safeToSpend()).thenAnswer((_) async => _cast(free));
    when(() => bills.list(owner: owner))
        .thenAnswer((_) async => _cast(listing));
    when(() => insights.overview(scope, InsightPeriod.month))
        .thenAnswer((_) async => _cast(overview));
  }

  final loaded = (
    free: Ok<Object>(safeToSpendOf()),
    listing: Ok<Object>(BillPage(bills: [testBill(payee: 'Energia Exemplo')])),
    overview: Ok<Object>(
      overviewWith(
        const CardsSummary(
          bill: Money(50_000),
          count: 1,
          dueOn: CalendarDate(2026, 10, 15),
        ),
      ),
    ),
  );

  test('publishes fresh numbers and drops the connection', () async {
    answer(
      free: loaded.free,
      listing: loaded.listing,
      overview: loaded.overview,
    );

    final outcome = await refresh()(const WidgetSettings());

    expect(outcome, WidgetRefresh.refreshed);
    expect(opened, [_session]);
    expect(closed, 1);
    final values = publisher.last!.values;
    expect(values[WidgetKeys.hidden], isFalse);
    expect(values[WidgetKeys.updatedTime], '12:00');
    expect(values[WidgetKeys.billPayee], 'Energia Exemplo');
    expect(values[WidgetKeys.cardDue], '15/10');
  });

  test('reads the scope the app was left on', () async {
    answer(
      free: loaded.free,
      listing: loaded.listing,
      overview: loaded.overview,
      scope: EntityScope.consolidated,
      owner: null,
    );

    final outcome = await refresh()(
      const WidgetSettings(scope: EntityScope.consolidated),
    );

    expect(outcome, WidgetRefresh.refreshed);
    verify(
      () => insights.overview(EntityScope.consolidated, InsightPeriod.month),
    );
  });

  test('a revoked session empties the widget', () async {
    answer(
      free: const Err(UnauthorizedFailure()),
      listing: const Err(UnauthorizedFailure()),
      overview: loaded.overview,
    );

    final outcome = await refresh()(const WidgetSettings());

    expect(outcome, WidgetRefresh.unauthorized);
    expect(publisher.cleared, 1);
    expect(publisher.published, isEmpty);
    expect(closed, 1);
  });

  test('offline keeps the last numbers and their time', () async {
    answer(
      free: const Err(NetworkFailure()),
      listing: const Err(NetworkFailure()),
      overview: const Err(NetworkFailure()),
    );

    final outcome = await refresh()(const WidgetSettings());

    expect(outcome, WidgetRefresh.unreachable);
    expect(publisher.published, isEmpty);
    expect(publisher.cleared, 0);
    expect(closed, 1);
  });

  test('a part that fails keeps its last value', () async {
    answer(
      free: const Err(ServerFailure()),
      listing: loaded.listing,
      overview: const Err(NetworkFailure()),
    );

    final outcome = await refresh()(const WidgetSettings());

    expect(outcome, WidgetRefresh.refreshed);
    final values = publisher.last!.values;
    expect(values.keys, isNot(contains(WidgetKeys.safeAmount)));
    expect(values.keys, isNot(contains(WidgetKeys.cardAmount)));
    expect(values[WidgetKeys.billPayee], 'Energia Exemplo');
  });

  test('with amounts off the widget it fetches nothing, not even the '
      'session', () async {
    final store = _CountingStore(_session);
    final masked = RefreshHomeWidget(
      credentials: store,
      open: (session) => fail('nothing should be fetched'),
      publisher: publisher,
      clock: FixedClock(testNow),
    );

    final outcome = await masked(const WidgetSettings(privacyMode: true));

    expect(outcome, WidgetRefresh.masked);
    expect(store.reads, 0);
    expect(publisher.last!.values, {WidgetKeys.hidden: true});
    verifyZeroInteractions(outlook);
  });

  test('signed out, it empties the widget without a request', () async {
    final outcome = await refresh(session: null)(const WidgetSettings());

    expect(outcome, WidgetRefresh.signedOut);
    expect(publisher.cleared, 1);
    expect(opened, isEmpty);
  });
}

Result<T> _cast<T>(Result<Object> result) => switch (result) {
  Ok(:final value) => Ok(value as T),
  Err(:final failure) => Err(failure),
};

final class _CountingStore implements CredentialStore {
  new(this._credentials);

  final ServerCredentials _credentials;
  int reads = 0;

  @override
  Future<ServerCredentials?> read() async {
    reads++;
    return _credentials;
  }

  @override
  Future<void> write(ServerCredentials credentials) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<ServerCredentials?> readLegacy() async => null;

  @override
  Future<void> clearLegacy() async {}
}
