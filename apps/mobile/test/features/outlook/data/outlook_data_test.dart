import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/outlook/data/api_outlook_repository.dart';
import 'package:cashdeck/features/outlook/data/fake_outlook_repository.dart';
import 'package:cashdeck/features/outlook/domain/net_worth.dart';
import 'package:cashdeck/features/outlook/domain/safe_to_spend.dart';
import 'package:cashdeck/features/outlook/outlook_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';

T _valueOf<T>(Result<T> result) => (result as Ok<T>).value;

Map<String, Object?> _money(int cents) => {'cents': cents, 'currency': 'BRL'};

Map<String, Object?> _composition(int total) => {
  'cash': _money(100_000),
  'investments': _money(total),
  'cardDebt': _money(100_000),
  'assets': _money(total + 100_000),
  'liabilities': _money(100_000),
  'total': _money(total),
};

Map<String, Object?> _safeToSpendJson({bool income = true}) => {
  'asOf': '2026-10-08',
  'basis': 'CASH',
  'plan': null,
  'cashShortBy': _money(12_000),
  'cash': _money(400_000),
  'reserve': _money(50_000),
  'total': _money(-12_000),
  'daily': _money(0),
  'days': 23,
  'until': '2026-10-31',
  'income': income ? {'on': '2026-10-20', 'amount': _money(700_000)} : null,
  'shortBy': _money(12_000),
  'lines': [
    {
      'kind': 'CARD',
      'label': 'Card One',
      'amount': _money(-420_000),
      'on': '2026-10-15',
    },
    {'kind': 'RESERVE', 'label': '', 'amount': _money(8_000), 'on': null},
  ],
};

Map<String, Object?> _netWorthJson({Object? percent = 2.5}) => {
  'asOf': '2026-10-08',
  'current': _composition(900_000),
  'fromLastMonth': {'amount': _money(22_000), 'percent': percent},
  'fromYearAgo': {'amount': _money(-5_000), 'percent': null},
  'entities': [
    {'kind': 'PF', 'current': _composition(900_000)},
  ],
  'series': [
    {
      'on': '2026-09-30',
      'assets': _money(978_000),
      'liabilities': _money(100_000),
      'total': _money(878_000),
    },
    {
      'on': '2026-10-08',
      'assets': _money(1_000_000),
      'liabilities': _money(100_000),
      'total': _money(900_000),
    },
  ],
};

void main() {
  group('ApiOutlookRepository', () {
    test('reads safe to spend with its lines and income', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {'data': _safeToSpendJson()}),
      );
      final free = _valueOf(await ApiOutlookRepository(dio).safeToSpend());

      expect(free.total, const Money(-12_000));
      expect(free.isShort, isTrue);
      expect(free.days, 23);
      expect(free.until, const CalendarDate(2026, 10, 31));
      expect(
        free.income,
        const ExpectedIncome(
          on: CalendarDate(2026, 10, 20),
          amount: Money(700_000),
        ),
      );
      expect(free.lines.first.kind, SafeToSpendLineKind.card);
      expect(free.lines.first.on, const CalendarDate(2026, 10, 15));
      expect(free.lines.last.kind, SafeToSpendLineKind.reserve);
      expect(free.lines.last.on, isNull);
      expect(
        adapterOf(dio).requests.single.path,
        '/api/v1/home/personal/safe-to-spend',
      );
    });

    test('reads a loan installment and a kind it does not know yet', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {
          'data': {
            ..._safeToSpendJson(),
            'lines': [
              for (final kind in ['LOAN', 'SOMETHING_NEW'])
                {
                  'kind': kind,
                  'label': 'Banco Exemplo',
                  'amount': _money(-300_000),
                  'on': '2026-10-17',
                },
            ],
          },
        }),
      );
      final free = _valueOf(await ApiOutlookRepository(dio).safeToSpend());

      expect(free.lines.map((line) => line.kind), [
        SafeToSpendLineKind.loan,
        SafeToSpendLineKind.fixed,
      ]);
    });

    test('asks the company home for the company figure', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {
          'data': {
            ..._safeToSpendJson(),
            'lines': [
              {
                'kind': 'BUDGET',
                'label': 'Software',
                'amount': _money(-40_000),
                'on': null,
              },
            ],
          },
        }),
      );
      final free = _valueOf(
        await ApiOutlookRepository(dio).safeToSpend(entity: EntityKind.company),
      );

      expect(free.lines.single.kind, SafeToSpendLineKind.budget);
      expect(free.lines.single.label, 'Software');
      expect(
        adapterOf(dio).requests.single.path,
        '/api/v1/home/company/safe-to-spend',
      );
    });

    test('reads the monthly plan of a person', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {
          'data': {
            ..._safeToSpendJson(income: false),
            'basis': 'MONTH',
            'plan': {
              'income': _money(2_400_000),
              'typical': _money(2_000_000),
              'received': _money(2_400_000),
              'savings': _money(650_000),
              'savingsSet': true,
              'months': 3,
              'sources': 2,
            },
            'cashShortBy': _money(0),
            'lines': [
              for (final kind in ['INCOME', 'SAVINGS', 'SPENT_CARD'])
                {'kind': kind, 'label': '', 'amount': _money(1), 'on': null},
              {
                'kind': 'SPENT_ACCOUNT',
                'label': '',
                'amount': _money(1),
                'on': null,
              },
            ],
          },
        }),
      );
      final free = _valueOf(await ApiOutlookRepository(dio).safeToSpend());

      expect(free.basis, SafeToSpendBasis.month);
      expect(
        free.plan,
        const SpendingPlan(
          income: Money(2_400_000),
          typical: Money(2_000_000),
          received: Money(2_400_000),
          savings: Money(650_000),
          savingsSet: true,
          months: 3,
          sources: 2,
        ),
      );
      expect(free.plan?.fromReceived, isTrue);
      expect(free.isCashShort, isFalse);
      expect(free.lines.map((line) => line.kind), [
        SafeToSpendLineKind.income,
        SafeToSpendLineKind.savings,
        SafeToSpendLineKind.spentCard,
        SafeToSpendLineKind.spentAccount,
      ]);
    });

    test('sets the savings target, or clears it with null', () async {
      final dio = stubDio(
        (_) => const StubResponse(200, {'data': <String, Object?>{}}),
      );
      final repository = ApiOutlookRepository(dio);

      expect(
        await repository.setSavingsTarget(const Money(300_000)),
        isA<Ok<void>>(),
      );
      expect(await repository.setSavingsTarget(null), isA<Ok<void>>());
      final requests = adapterOf(dio).requests;
      expect(requests.first.path, '/api/v1/home/personal/spending-plan');
      expect(requests.first.method, 'PUT');
      expect(requests.first.data, {
        'savings': {'cents': 300_000, 'currency': 'BRL'},
      });
      expect(requests.last.data, {'savings': null});
    });

    test('lists the payers and saves the chosen ones', () async {
      final dio = stubDio(
        (options) => StubResponse(200, {
          'data': options.method == 'GET'
              ? {
                  'items': [
                    {
                      'taxId': '11222333000181',
                      'name': 'Cliente Exemplo',
                      'total': _money(900_000),
                      'months': 3,
                      'lastOn': '2026-10-05',
                      'selected': true,
                    },
                  ],
                }
              : <String, Object?>{},
        }),
      );
      final repository = ApiOutlookRepository(dio);
      const source = IncomeSource(
        taxId: '11222333000181',
        name: 'Cliente Exemplo',
      );

      expect(_valueOf(await repository.incomeSources()), [
        const IncomeSourceCandidate(
          source: source,
          total: Money(900_000),
          months: 3,
          lastOn: CalendarDate(2026, 10, 5),
          selected: true,
        ),
      ]);
      expect(await repository.setIncomeSources([source]), isA<Ok<void>>());
      final requests = adapterOf(dio).requests;
      expect(requests.first.path, '/api/v1/home/personal/income-sources');
      expect(requests.last.data, {
        'incomeSources': [
          {'taxId': '11222333000181', 'name': 'Cliente Exemplo'},
        ],
      });
    });

    test('reads safe to spend without a known income', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {'data': _safeToSpendJson(income: false)}),
      );
      final free = _valueOf(await ApiOutlookRepository(dio).safeToSpend());

      expect(free.income, isNull);
    });

    test('reads goods and loans when the server sends them', () async {
      final json = _netWorthJson();
      final dio = stubDio(
        (_) => StubResponse(200, {
          'data': {
            ...json,
            'current': {
              ..._composition(900_000),
              'realEstate': _money(50_000_000),
              'vehicles': _money(9_000_000),
              'otherAssets': _money(100_000),
              'loanDebt': _money(19_000_000),
            },
          },
        }),
      );
      final worth = _valueOf(
        await ApiOutlookRepository(dio)
            .netWorth(EntityScope.personal, NetWorthPeriod.sixMonths),
      );

      expect(worth.current.realEstate, const Money(50_000_000));
      expect(worth.current.vehicles, const Money(9_000_000));
      expect(worth.current.otherAssets, const Money(100_000));
      expect(worth.current.loanDebt, const Money(19_000_000));
      expect(worth.entities.single.current.loanDebt, const Money(0));
    });

    test('reads net worth and sends the window and the entity', () async {
      final dio = stubDio((_) => StubResponse(200, {'data': _netWorthJson()}));
      final worth = _valueOf(
        await ApiOutlookRepository(dio)
            .netWorth(EntityScope.personal, NetWorthPeriod.sixMonths),
      );

      expect(worth.current.total, const Money(900_000));
      expect(worth.fromLastMonth.percent, 2.5);
      expect(worth.fromLastMonth.direction, 1);
      expect(worth.fromYearAgo.percent, isNull);
      expect(worth.fromYearAgo.direction, -1);
      expect(worth.entities.single.kind, EntityKind.personal);
      expect(worth.series, hasLength(2));
      expect(worth.series.first.on, const CalendarDate(2026, 9, 30));
      final request = adapterOf(dio).requests.single;
      expect(request.path, '/api/v1/net-worth');
      expect(request.queryParameters, {'months': 6, 'entity': 'PF'});
    });

    test(
      'reads a whole percent and leaves the entity out when consolidated',
      () async {
        final dio = stubDio(
          (_) => StubResponse(200, {'data': _netWorthJson(percent: 3)}),
        );
        final worth = _valueOf(
          await ApiOutlookRepository(dio)
              .netWorth(EntityScope.consolidated, NetWorthPeriod.twelveMonths),
        );

        expect(worth.fromLastMonth.percent, 3.0);
        expect(adapterOf(dio).requests.single.queryParameters, {'months': 12});
      },
    );

    test(
      'turns a malformed percent and a server error into failures',
      () async {
        final malformed = stubDio(
          (_) => StubResponse(200, {'data': _netWorthJson(percent: 'high')}),
        );
        expect(
          await ApiOutlookRepository(malformed)
              .netWorth(EntityScope.personal, NetWorthPeriod.twelveMonths),
          isA<Err<NetWorth>>(),
        );

        final down = stubDio((_) => const StubResponse(500, {'error': 'down'}));
        final result = await ApiOutlookRepository(down).safeToSpend();
        expect((result as Err<SafeToSpend>).failure, isA<AppFailure>());
      },
    );
  });

  group('FakeOutlookRepository', () {
    final repository = FakeOutlookRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );

    test('plans the month from the typical income to the free total', () async {
      final free = _valueOf(await repository.safeToSpend());

      final lines = free.lines.fold(0, (sum, line) => sum + line.amount.cents);
      expect(free.basis, SafeToSpendBasis.month);
      expect(lines, free.total.cents);
      expect(free.until, const CalendarDate(2026, 10, 31));
      expect(free.isShort, isFalse);
      expect(free.plan?.savingsSet, isFalse);
    });

    test('keeps the savings target until it is cleared', () async {
      final target = FakeOutlookRepository(
        FixedClock(testNow),
        latency: Duration.zero,
      );
      await target.setSavingsTarget(const Money(2_400_000));
      final saved = _valueOf(await target.safeToSpend());
      expect(saved.plan?.savings, const Money(2_400_000));
      expect(saved.plan?.savingsSet, isTrue);
      expect(saved.isShort, isTrue);
      expect(saved.daily, const Money(0));

      await target.setSavingsTarget(null);
      final typical = _valueOf(await target.safeToSpend());
      expect(typical.plan?.savings, FakeOutlookRepository.typicalSavings);
    });

    test('remembers the chosen payers', () async {
      final target = FakeOutlookRepository(
        FixedClock(testNow),
        latency: Duration.zero,
      );
      final payers = _valueOf(await target.incomeSources());
      expect(payers.where((payer) => payer.selected), isEmpty);

      await target.setIncomeSources([payers.first.source]);
      final chosen = _valueOf(await target.incomeSources());
      expect(chosen.first.selected, isTrue);
      expect(_valueOf(await target.safeToSpend()).plan?.sources, 1);
    });

    test('the company runs to the month end with budgets kept', () async {
      final free = _valueOf(
        await repository.safeToSpend(entity: EntityKind.company),
      );

      final lines = free.lines.fold(0, (sum, line) => sum + line.amount.cents);
      expect(free.cash.cents + lines, free.total.cents);
      expect(free.income, isNull);
      expect(free.until, const CalendarDate(2026, 10, 31));
      expect(
        free.lines.where((line) => line.kind == SafeToSpendLineKind.budget),
        hasLength(2),
      );
    });

    test('sums the entities in scope and ends the series today', () async {
      final both = _valueOf(
        await repository.netWorth(
          EntityScope.consolidated,
          NetWorthPeriod.twelveMonths,
        ),
      );
      expect(
        both.current.total,
        FakeOutlookRepository.personal.total +
            FakeOutlookRepository.company.total,
      );
      expect(both.entities, hasLength(2));
      expect(both.series, hasLength(13));
      expect(both.series.first.on, const CalendarDate(2025, 10, 31));
      expect(both.series.last.on, testToday);

      final company = _valueOf(
        await repository.netWorth(
          EntityScope.company,
          NetWorthPeriod.sixMonths,
        ),
      );
      expect(company.current, FakeOutlookRepository.company);
      expect(company.series, hasLength(7));
      expect(company.fromLastMonth.amount, FakeOutlookRepository.monthlyGrowth);
      expect(company.isEmpty, isFalse);
    });
  });

  test('the backend picks the repository', () {
    ProviderContainer containerFor(Backend backend) {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(backend: backend, apiBaseUrl: 'https://x.test'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    expect(
      containerFor(Backend.api).read(outlookRepositoryProvider),
      isA<ApiOutlookRepository>(),
    );
    expect(
      containerFor(Backend.fake).read(outlookRepositoryProvider),
      isA<FakeOutlookRepository>(),
    );
  });
}
