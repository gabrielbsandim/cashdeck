import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/budgets_providers.dart';
import 'package:cashdeck/features/budgets/data/api_budgets_repository.dart';
import 'package:cashdeck/features/budgets/data/budget_dtos.dart';
import 'package:cashdeck/features/budgets/data/fake_budgets_repository.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';
import '../budget_builders.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

Map<String, dynamic> _money(int cents) => {'cents': cents, 'currency': 'BRL'};

Map<String, dynamic> _usage(int spent, String level) => {
  'available': _money(75_000),
  'spent': _money(spent),
  'remaining': _money(75_000 - spent),
  'percent': spent * 100 ~/ 75_000,
  'level': level,
};

Map<String, dynamic> monthJson() => {
  'month': '2026-10',
  'total': _usage(66_400, 'NEAR'),
  'items': [
    {
      'id': 'budget-1',
      'categoryId': 'cat-groceries',
      'key': 'groceries',
      'name': 'Mercado',
      'limit': _money(70_000),
      'carried': _money(5_000),
      'rollover': true,
      ..._usage(80_000, 'REACHED'),
    },
  ],
  'unbudgeted': [
    {
      'categoryId': 'cat-pets',
      'key': null,
      'name': 'Pet',
      'spent': _money(9_000),
    },
  ],
};

Map<String, dynamic> suggestionsJson() => {
  'month': '2026-10',
  'basedOn': ['2026-07', '2026-08', '2026-09'],
  'items': [
    {
      'categoryId': 'cat-groceries',
      'key': 'groceries',
      'name': 'Mercado',
      'months': [_money(60_000), _money(64_000), _money(70_000)],
      'suggested': _money(65_000),
      'current': _money(70_000),
    },
    {
      'categoryId': 'cat-pets',
      'key': null,
      'name': 'Pet',
      'months': [_money(9_000)],
      'suggested': _money(10_000),
      'current': null,
    },
  ],
};

void main() {
  group('dtos', () {
    test('read a month with its levels and the unbudgeted spend', () {
      final month = budgetMonthFromJson(monthJson());
      expect(month.month, october);
      expect(month.total.level, BudgetLevel.near);
      final item = month.items.single;
      expect(item.category, groceries);
      expect(item.carried, const Money(5_000));
      expect(item.rollover, isTrue);
      expect(item.usage.level, BudgetLevel.reached);
      expect(item.usage.over, isTrue);
      expect(month.unbudgeted.single.category.key, isNull);
      expect(budgetUsageFromJson(_usage(100, 'OK')).level, BudgetLevel.ok);
    });

    test('read suggestions and write the accepted limits', () {
      final suggestions = budgetSuggestionsFromJson(suggestionsJson());
      expect(suggestions.basedOn, const [
        YearMonth(2026, 7),
        YearMonth(2026, 8),
        YearMonth(2026, 9),
      ]);
      expect(suggestions.items.first.current, const Money(70_000));
      expect(suggestions.items.first.months, hasLength(3));
      expect(suggestions.items.last.current, isNull);
      expect(
        acceptToJson(october, const [
          (categoryId: 'cat-pets', limit: Money(10_000)),
        ]),
        {
          'entity': 'PF',
          'month': '2026-10',
          'items': [
            {'categoryId': 'cat-pets', 'limitCents': 10_000},
          ],
        },
      );
    });
  });

  test('the api reads and changes budgets', () async {
    final dio = stubDio((options) {
      final key = '${options.method} ${options.path}';
      return switch (key) {
        'GET /api/v1/budgets/suggestions' => StubResponse(200, {
          'data': suggestionsJson(),
        }),
        'POST /api/v1/budgets' => StubResponse(201, {'data': monthJson()}),
        _ => StubResponse(200, {'data': monthJson()}),
      };
    });
    final repository = ApiBudgetsRepository(dio);

    expect(_ok(await repository.month(october)).month, october);
    expect(
      _ok(await repository.create(october, 'cat-pets', const Money(10_000)))
          .items,
      hasLength(1),
    );
    expect(
      _ok(
        await repository.update(
          'budget 1',
          limit: const Money(80_000),
          rollover: true,
        ),
      ).month,
      october,
    );
    expect(_ok(await repository.delete('budget-1')).month, october);
    expect(_ok(await repository.copyToNext(october)).month, october);
    expect(_ok(await repository.suggestions(october)).items, hasLength(2));
    expect(
      _ok(
        await repository.accept(october, const [
          (categoryId: 'cat-pets', limit: Money(10_000)),
        ]),
      ).month,
      october,
    );

    final requests = adapterOf(dio).requests;
    expect(requests.first.queryParameters, {
      'entity': 'PF',
      'month': '2026-10',
    });
    expect(requests[1].data, {
      'entity': 'PF',
      'month': '2026-10',
      'categoryId': 'cat-pets',
      'limitCents': 10_000,
      'rollover': false,
    });
    expect(requests[2].path, '/api/v1/budgets/budget%201');
    expect(requests[2].data, {'limitCents': 80_000, 'rollover': true});
    expect(requests[3].method, 'DELETE');
    expect(requests[4].path, '/api/v1/budgets/copy');
    expect(requests[4].data, {'entity': 'PF', 'month': '2026-10'});
    expect(requests.last.path, '/api/v1/budgets/suggestions');
    expect(requests.last.method, 'POST');
  });

  group('fake', () {
    late FakeBudgetsRepository repository;

    setUp(
      () => repository = FakeBudgetsRepository(
        FixedClock(testNow),
        latency: Duration.zero,
      ),
    );

    test('seeds a month with every level, fullest first', () async {
      final month = _ok(await repository.month(october));
      expect(month.items.map((item) => item.id), [
        'budget-restaurants',
        'budget-groceries',
        'budget-transport',
      ]);
      expect(month.items.map((item) => item.usage.level), [
        BudgetLevel.reached,
        BudgetLevel.near,
        BudgetLevel.ok,
      ]);
      expect(month.items[1].usage.available, const Money(75_000));
      expect(month.unbudgeted.single.category.id, 'cat-leisure');
      expect(month.total.spent, const Money(140_500));

      final past = _ok(await repository.month(const YearMonth(2026, 9)));
      expect(past.isEmpty, isTrue);
      expect(past.unbudgeted, hasLength(5));
      expect(past.total.percent, 0);
    });

    test('creates, edits and deletes a limit', () async {
      expect(
        await repository.create(october, 'cat-groceries', const Money(1)),
        isA<Err<BudgetMonth>>().having(
          (err) => err.failure,
          'failure',
          isA<ValidationFailure>(),
        ),
      );
      final created = _ok(
        await repository.create(
          october,
          'cat-leisure',
          const Money(20_000),
          rollover: true,
        ),
      );
      expect(created.unbudgeted, isEmpty);
      final leisure = created.items.firstWhere(
        (item) => item.category.id == 'cat-leisure',
      );
      expect(leisure.rollover, isTrue);
      final other = _ok(
        await repository.create(october, 'cat-unknown', const Money(100)),
      );
      expect(
        other.items.map((item) => item.category),
        contains(const SpendCategory(id: 'cat-unknown', name: 'cat-unknown')),
      );

      final updated = _ok(
        await repository.update(
          leisure.id,
          limit: const Money(15_000),
          rollover: false,
        ),
      );
      expect(
        updated.items.firstWhere((item) => item.id == leisure.id).limit,
        const Money(15_000),
      );
      expect(
        await repository.update('gone', limit: const Money(1), rollover: true),
        const Err<BudgetMonth>(NotFoundFailure()),
      );
      expect(
        _ok(await repository.delete(leisure.id)).unbudgeted.single.category.id,
        'cat-leisure',
      );
      expect(
        await repository.delete(leisure.id),
        const Err<BudgetMonth>(NotFoundFailure()),
      );
    });

    test('copies to the next month carrying what rolls over', () async {
      final next = _ok(await repository.copyToNext(october));
      expect(next.month, const YearMonth(2026, 11));
      expect(next.items, hasLength(3));
      final carried = {
        for (final item in next.items) item.category.id: item.carried,
      };
      expect(carried['cat-groceries'], const Money(8_600));
      expect(carried['cat-restaurants'], const Money(0));
      expect(next.total.spent, const Money(0));
      final again = _ok(await repository.copyToNext(october));
      expect(again.items, hasLength(3));
    });

    test('suggests from the last three months and accepts them', () async {
      final suggestions = _ok(await repository.suggestions(october));
      expect(suggestions.basedOn, const [
        YearMonth(2026, 7),
        YearMonth(2026, 8),
        YearMonth(2026, 9),
      ]);
      expect(suggestions.items, hasLength(5));
      expect(
        suggestions.items.every((item) => item.suggested.cents % 1_000 == 0),
        isTrue,
      );
      final groceries = suggestions.items.firstWhere(
        (item) => item.category.id == 'cat-groceries',
      );
      expect(groceries.current, const Money(70_000));
      expect(groceries.months, hasLength(3));

      final accepted = _ok(
        await repository.accept(october, const [
          (categoryId: 'cat-groceries', limit: Money(80_000)),
          (categoryId: 'cat-pets', limit: Money(10_000)),
        ]),
      );
      expect(accepted.items, hasLength(4));
      expect(
        accepted.items
            .firstWhere((item) => item.category.id == 'cat-groceries')
            .limit,
        const Money(80_000),
      );
    });
  });

  test('the backend picks the repository', () {
    ProviderContainer containerFor(Backend backend) {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(backend: backend, apiBaseUrl: 'https://api.test'),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    expect(
      containerFor(Backend.fake).read(budgetsRepositoryProvider),
      isA<FakeBudgetsRepository>(),
    );
    expect(
      containerFor(Backend.api).read(budgetsRepositoryProvider),
      isA<ApiBudgetsRepository>(),
    );
  });
}
