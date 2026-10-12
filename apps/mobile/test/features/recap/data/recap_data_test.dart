import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/recap/data/api_recap_repository.dart';
import 'package:cashdeck/features/recap/data/fake_recap_repository.dart';
import 'package:cashdeck/features/recap/data/recap_dtos.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:cashdeck/features/recap/recap_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/stub_http_adapter.dart';
import '../recap_builders.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

void main() {
  test('reads every figure of a recap', () {
    final recap = monthlyRecapFromJson(recapJson());
    expect(recap.month, const YearMonth(2026, 9));
    expect(recap.flow.net, const Money(363_020));
    expect(recap.previousFlow.income, const Money(500_000));
    expect(recap.expensesChange.percent, 17);
    expect(recap.savingsPercent, 61);
    expect(recap.previousSavingsPercent, 60);
    expect(recap.topCategory?.key, 'groceries');
    expect(recap.topCategory?.sharePercent, 76);
    expect(recap.rose.single.change?.percent, isNull);
    expect(recap.fell.single.change?.amount, const Money(-90_000));
    expect(recap.started.single.name, 'Video Max');
    expect(recap.stopped.single.amount, const Money(8_000));
    expect(recap.netWorth?.change.percent, 56);
    expect(recap.storySource, RecapStorySource.ai);
  });

  test('reads a month without the optional figures', () {
    final recap = monthlyRecapFromJson({
      ...recapJson(source: 'TEMPLATE'),
      'savings': {'percent': null, 'previousPercent': null},
      'topCategory': null,
      'changes': {'rose': <Object>[], 'fell': <Object>[]},
      'subscriptions': {'started': <Object>[], 'stopped': <Object>[]},
      'netWorth': null,
    });
    expect(recap.storySource, RecapStorySource.template);
    expect(recap.pages, [RecapPage.flow, RecapPage.story]);
  });

  test('the api asks for the entity recap in the given language', () async {
    final dio = stubDio((_) => StubResponse(200, {'data': recapJson()}));
    final repository = ApiRecapRepository(dio);
    final recap = _ok(
      await repository.get(
        const YearMonth(2026, 9),
        locale: 'en',
        entity: EntityKind.personal,
      ),
    );
    expect(recap.month, const YearMonth(2026, 9));
    await repository.get(
      const YearMonth(2026, 9),
      locale: 'pt',
      entity: EntityKind.company,
    );
    final requests = adapterOf(dio).requests;
    expect(requests.first.path, '/api/v1/recaps/2026-09');
    expect(requests.map((request) => request.queryParameters), [
      {'entity': 'PF', 'locale': 'en'},
      {'entity': 'PJ', 'locale': 'pt'},
    ]);
  });

  test('the api turns a refused month into a failure', () async {
    final dio = stubDio(
      (_) => const StubResponse(422, {
        'error': {'code': 'VALIDATION', 'message': 'Not closed.'},
      }),
    );
    expect(
      await ApiRecapRepository(dio).get(
        const YearMonth(2026, 10),
        locale: 'pt',
        entity: EntityKind.personal,
      ),
      isA<Err<MonthlyRecap>>().having(
        (result) => result.failure,
        'failure',
        isA<ValidationFailure>(),
      ),
    );
  });

  test('the fake tells the same month in each language', () async {
    const repository = FakeRecapRepository(latency: Duration.zero);
    const month = YearMonth(2026, 9);
    const personal = EntityKind.personal;
    final pt = _ok(await repository.get(month, locale: 'pt', entity: personal));
    final en = _ok(await repository.get(month, locale: 'en', entity: personal));
    final other = _ok(
      await repository.get(month, locale: 'es', entity: EntityKind.company),
    );
    expect(pt.month, month);
    expect(pt.pages, RecapPage.values);
    expect(en.story, isNot(pt.story));
    expect(other.story, pt.story);
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
      containerFor(Backend.fake).read(recapRepositoryProvider),
      isA<FakeRecapRepository>(),
    );
    final api = containerFor(Backend.api);
    expect(api.read(recapRepositoryProvider), isA<ApiRecapRepository>());
    expect(api.read(getMonthlyRecapProvider), isNotNull);
  });
}
