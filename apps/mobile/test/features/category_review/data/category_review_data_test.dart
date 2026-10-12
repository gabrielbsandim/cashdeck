import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/category_review/category_review_providers.dart';
import 'package:cashdeck/features/category_review/data/api_category_review_repository.dart';
import 'package:cashdeck/features/category_review/data/category_review_dtos.dart';
import 'package:cashdeck/features/category_review/data/fake_category_review_repository.dart';
import 'package:cashdeck/features/category_review/domain/category_review.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

Map<String, dynamic> _group({Object? confidence = 0.6}) => {
  'id': 'personal|OUT:padaria exemplo',
  'entityKind': 'PF',
  'merchant': 'Padaria Exemplo',
  'pattern': 'padaria exemplo',
  'counterparty': null,
  'direction': 'OUT',
  'count': 2,
  'total': {'cents': 1500, 'currency': 'BRL'},
  'reasons': ['LOW_CONFIDENCE', 'SOMETHING_NEW'],
  'suggestedCategoryId': 'cat-groceries',
  'confidence': confidence,
  'canCreateRule': true,
  'lastBookedOn': '2026-10-07',
  'transactionIds': ['tx-1', 'tx-2'],
};

const Map<String, dynamic> _suggestion = {
  'id': 'personal|OUT|mercado exemplo|cat-groceries',
  'entityKind': 'PF',
  'merchant': 'Mercado Exemplo',
  'pattern': 'mercado exemplo',
  'counterparty': null,
  'direction': 'OUT',
  'categoryId': 'cat-groceries',
  'count': 3,
};

Map<String, dynamic> _rule({
  String? entityKind,
  String? direction,
  String pattern = 'academia exemplo',
}) => {
  'id': 'rule-1',
  'entityKind': entityKind,
  'pattern': pattern,
  'counterparty': pattern.isEmpty ? '11222333000181' : null,
  'direction': direction,
  'categoryId': 'cat-leisure',
  'priority': 0,
  'createdAt': '2026-10-08T12:00:00.000Z',
};

void main() {
  group('dtos', () {
    test('read a queue, skipping reasons the app does not know', () {
      final queue = reviewQueueFromJson({
        'pending': 2,
        'groups': [_group(), _group(confidence: null)],
        'suggestions': [_suggestion],
      });

      final group = queue.groups.first;
      expect(queue.pending, 2);
      expect(group.owner, EntityKind.personal);
      expect(group.direction, FlowDirection.outgoing);
      expect(group.total, const Money(1500));
      expect(group.reasons, [ReviewReason.lowConfidence]);
      expect(group.confidence, 0.6);
      expect(queue.groups.last.confidence, isNull);
      expect(queue.suggestions.single.count, 3);
    });

    test('read rules with or without an entity and a direction', () {
      final shared = categoryRuleFromJson(_rule(pattern: ''));
      final scoped = categoryRuleFromJson(
        _rule(entityKind: 'PJ', direction: 'IN'),
      );

      expect(shared.owner, isNull);
      expect(shared.direction, isNull);
      expect(shared.counterparty, '11222333000181');
      expect(scoped.owner, EntityKind.company);
      expect(scoped.direction, FlowDirection.incoming);
      expect(
        categorizeOutcomeFromJson({
          'updated': 2,
          'similarUpdated': 1,
          'rule': _rule(),
        }).rule?.id,
        'rule-1',
      );
      expect(
        categorizeOutcomeFromJson({'updated': 1, 'rule': null}),
        const CategorizeOutcome(updated: 1),
      );
    });

    test('a change sends only what changed', () {
      expect(categoryRuleChangeToJson(const CategoryRuleChange()), isEmpty);
      expect(
        categoryRuleChangeToJson(
          const CategoryRuleChange(pattern: ' padaria ', categoryId: 'cat-1'),
        ),
        {'pattern': 'padaria', 'categoryId': 'cat-1'},
      );
    });
  });

  test('the api reads the queue, decides and edits rules', () async {
    final dio = stubDio((options) {
      final key = '${options.method} ${options.path}';
      return switch (key) {
        'GET /api/v1/categories/review' => StubResponse(200, {
          'data': {
            'pending': 2,
            'groups': [_group()],
            'suggestions': [_suggestion],
          },
        }),
        'POST /api/v1/categories/review/groups' => StubResponse(200, {
          'data': {'updated': 2, 'similarUpdated': 0, 'rule': _rule()},
        }),
        'POST /api/v1/categories/review/suggestions/accept' => StubResponse(
          201,
          {
            'data': {'updated': 0, 'similarUpdated': 3, 'rule': _rule()},
          },
        ),
        'POST /api/v1/categories/review/suggestions/dismiss' =>
          const StubResponse(200, {
            'data': {'id': 's'},
          }),
        'GET /api/v1/categories/rules' => StubResponse(200, {
          'data': [_rule()],
        }),
        'PATCH /api/v1/categories/rules/rule-1' => StubResponse(200, {
          'data': {'rule': _rule(), 'updated': 4},
        }),
        'DELETE /api/v1/categories/rules/rule-1' => const StubResponse(200, {
          'data': {'id': 'rule-1'},
        }),
        _ => const StubResponse(404),
      };
    });
    final repository = ApiCategoryReviewRepository(dio);

    expect(_ok(await repository.queue()).pending, 2);
    expect(
      _ok(await repository.queue(entity: EntityKind.company)).groups,
      hasLength(1),
    );
    expect(
      _ok(await repository.categorize(['tx-1'], 'cat-1', createRule: true))
          .rule
          ?.id,
      'rule-1',
    );
    expect(_ok(await repository.acceptSuggestion('s')).similarUpdated, 3);
    expect(await repository.dismissSuggestion('s'), isA<Ok<void>>());
    expect(_ok(await repository.rules()).single.id, 'rule-1');
    expect(
      _ok(
        await repository.updateRule(
          'rule-1',
          const CategoryRuleChange(categoryId: 'cat-1'),
        ),
      ).id,
      'rule-1',
    );
    expect(await repository.deleteRule('rule-1'), isA<Ok<void>>());
    expect(await repository.deleteRule('none'), isA<Err<void>>());

    final requests = adapterOf(dio).requests;
    expect(requests[0].queryParameters, isEmpty);
    expect(requests[1].queryParameters, {'entity': 'PJ'});
    expect(requests[2].data, {
      'transactionIds': ['tx-1'],
      'categoryId': 'cat-1',
      'createRule': true,
    });
    expect(requests[3].data, {'id': 's'});
    expect(requests[6].data, {'categoryId': 'cat-1'});
  });

  group('fake', () {
    FakeCategoryReviewRepository repository() => FakeCategoryReviewRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );

    test('filters the queue by entity', () async {
      final fake = repository();

      final both = _ok(await fake.queue());
      final company = _ok(await fake.queue(entity: EntityKind.company));

      expect(both.pending, 7);
      expect(both.groups, hasLength(3));
      expect(company.pending, 1);
      expect(company.suggestions, isEmpty);
    });

    test('settles groups and suggestions into rules', () async {
      final fake = repository();

      final settled = _ok(
        await fake.categorize(['review-5'], 'cat-fuel', createRule: true),
      );
      final plain = _ok(
        await fake.categorize(['review-1'], 'cat-food', createRule: false),
      );
      final accepted = _ok(await fake.acceptSuggestion('suggestion-market'));

      expect(settled.rule?.pattern, 'posto modelo');
      expect(plain.rule, isNull);
      expect(accepted.rule?.categoryId, 'cat-groceries');
      expect(_ok(await fake.queue()).pending, 1);
      expect(_ok(await fake.rules()), hasLength(4));
      expect(
        await fake.categorize(['review-1'], 'cat-1', createRule: false),
        const Err<CategorizeOutcome>(NotFoundFailure()),
      );
      expect(
        await fake.acceptSuggestion('suggestion-market'),
        const Err<CategorizeOutcome>(NotFoundFailure()),
      );
    });

    test('dismisses, edits and deletes', () async {
      final fake = repository();

      expect(
        await fake.dismissSuggestion('suggestion-market'),
        const Ok<void>(null),
      );
      expect(
        await fake.dismissSuggestion('suggestion-market'),
        const Err<void>(NotFoundFailure()),
      );
      final rules = _ok(await fake.rules());
      expect(rules.map((rule) => rule.matches), [
        'academia exemplo',
        'farmacia modelo',
      ]);
      final renamed = _ok(
        await fake.updateRule(
          'rule-gym',
          const CategoryRuleChange(pattern: ' academia nova '),
        ),
      );
      final recategorized = _ok(
        await fake.updateRule(
          'rule-gym',
          const CategoryRuleChange(categoryId: 'cat-health'),
        ),
      );
      expect(renamed.pattern, 'academia nova');
      expect(recategorized.pattern, 'academia nova');
      expect(recategorized.categoryId, 'cat-health');
      expect(
        await fake.updateRule('none', const CategoryRuleChange()),
        const Err<CategoryRule>(NotFoundFailure()),
      );
      expect(await fake.deleteRule('rule-gym'), const Ok<void>(null));
      expect(
        await fake.deleteRule('rule-gym'),
        const Err<void>(NotFoundFailure()),
      );
    });
  });

  test('the provider picks fake or api by the backend', () {
    final fake = ProviderContainer();
    addTearDown(fake.dispose);
    final api = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://api.test'),
        ),
      ],
    );
    addTearDown(api.dispose);

    expect(
      fake.read(categoryReviewRepositoryProvider),
      isA<FakeCategoryReviewRepository>(),
    );
    expect(
      api.read(categoryReviewRepositoryProvider),
      isA<ApiCategoryReviewRepository>(),
    );
    expect(fake.read(loadReviewQueueProvider), isNotNull);
    expect(fake.read(categorizeGroupProvider), isNotNull);
    expect(fake.read(acceptRuleSuggestionProvider), isNotNull);
    expect(fake.read(dismissRuleSuggestionProvider), isNotNull);
    expect(fake.read(listCategoryRulesProvider), isNotNull);
    expect(fake.read(updateCategoryRuleProvider), isNotNull);
    expect(fake.read(deleteCategoryRuleProvider), isNotNull);
  });
}
