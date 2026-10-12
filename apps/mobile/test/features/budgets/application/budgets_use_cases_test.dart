import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/budgets/application/budgets_use_cases.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../budget_builders.dart';

final class MockBudgetsRepository extends Mock implements BudgetsRepository;

final _month = BudgetMonth(
  month: october,
  total: usageAt(50),
  items: [itemAt(50)],
);

final _suggestions = BudgetSuggestions(
  month: october,
  basedOn: const [],
  items: [suggestionFor(groceries, 70_000)],
);

const List<BudgetLimit> _limits = [
  (categoryId: 'cat-groceries', limit: Money(70_000)),
];

void main() {
  late MockBudgetsRepository repository;

  setUp(() => repository = MockBudgetsRepository());

  test('each use case forwards to the repository', () async {
    when(() => repository.month(october)).thenAnswer((_) async => Ok(_month));
    when(
      () => repository.create(
        october,
        'cat-groceries',
        const Money(500),
        rollover: true,
      ),
    ).thenAnswer((_) async => Ok(_month));
    when(
      () => repository.update(
        'budget-1',
        limit: const Money(500),
        rollover: false,
      ),
    ).thenAnswer((_) async => Ok(_month));
    when(() => repository.delete('budget-1'))
        .thenAnswer((_) async => Ok(_month));
    when(() => repository.copyToNext(october))
        .thenAnswer((_) async => Ok(_month));
    when(() => repository.suggestions(october))
        .thenAnswer((_) async => Ok(_suggestions));
    when(() => repository.accept(october, _limits))
        .thenAnswer((_) async => Ok(_month));

    expect(await LoadBudgetMonth(repository).call(october), Ok(_month));
    final setLimit = SetBudgetLimit(repository);
    expect(
      await setLimit(
        month: october,
        categoryId: 'cat-groceries',
        limit: const Money(500),
        rollover: true,
      ),
      Ok(_month),
    );
    expect(
      await setLimit(
        month: october,
        categoryId: 'cat-groceries',
        limit: const Money(500),
        rollover: false,
        id: 'budget-1',
      ),
      Ok(_month),
    );
    expect(await DeleteBudget(repository).call('budget-1'), Ok(_month));
    expect(await CopyBudgets(repository).call(october), Ok(_month));
    expect(await SuggestBudgets(repository).call(october), Ok(_suggestions));
    expect(
      await AcceptBudgetSuggestions(repository).call(october, _limits),
      Ok(_month),
    );
  });

  test('a zero limit or nothing chosen never reaches the server', () async {
    expect(
      await SetBudgetLimit(repository).call(
        month: october,
        categoryId: 'cat-groceries',
        limit: const Money(0),
        rollover: false,
      ),
      const Err<BudgetMonth>(UnexpectedFailure()),
    );
    expect(
      await AcceptBudgetSuggestions(repository).call(october, const []),
      const Err<BudgetMonth>(UnexpectedFailure()),
    );
    verifyZeroInteractions(repository);
  });
}
