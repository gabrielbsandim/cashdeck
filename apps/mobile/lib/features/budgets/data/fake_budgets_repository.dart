import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/domain/budget.dart';

final class _Row {
  new({
    required this.id,
    required this.month,
    required this.categoryId,
    required this.limit,
    this.carried = const Money(0),
    this.rollover = false,
  });

  final String id;
  final YearMonth month;
  final String categoryId;
  Money limit;
  final Money carried;
  bool rollover;
}

const _categories = [
  SpendCategory(id: 'cat-groceries', key: 'groceries', name: 'Mercado'),
  SpendCategory(
    id: 'cat-restaurants',
    key: 'restaurants',
    name: 'Restaurantes',
  ),
  SpendCategory(id: 'cat-transport', key: 'transport', name: 'Transporte'),
  SpendCategory(id: 'cat-leisure', key: 'leisure', name: 'Lazer'),
  SpendCategory(id: 'cat-pets', name: 'Pet'),
];

/// What each category spends in a typical month, before the month's swing.
const Map<String, int> _baseSpend = {
  'cat-groceries': 64_000,
  'cat-restaurants': 46_000,
  'cat-transport': 31_000,
  'cat-leisure': 18_000,
  'cat-pets': 9_500,
};

/// This month's spending so the screens show every level: one near, one
/// past the limit, one comfortable.
const Map<String, int> _thisMonth = {
  'cat-groceries': 66_400,
  'cat-restaurants': 52_300,
  'cat-transport': 21_800,
  'cat-leisure': 18_000,
};

BudgetLevel _levelOf(int percent) => switch (percent) {
  >= 100 => BudgetLevel.reached,
  >= 80 => BudgetLevel.near,
  _ => BudgetLevel.ok,
};

BudgetUsage _usage(Money available, Money spent) {
  final percent = available.cents <= 0
      ? 0
      : spent.cents * 100 ~/ available.cents;
  return BudgetUsage(
    available: available,
    spent: spent,
    remaining: available - spent,
    percent: percent,
    level: _levelOf(percent),
  );
}

int _friendly(int cents) {
  final step = cents < 100_00 ? 10_00 : 50_00;
  return (cents / step).ceil() * step;
}

/// Fictional budgets in memory, with spending that changes month to month.
final class FakeBudgetsRepository implements BudgetsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  var _counter = 0;
  late final Map<String, _Row> _rows = {for (final row in _seed()) row.id: row};

  YearMonth get _current =>
      YearMonth.of(CalendarDate.brazilToday(_clock.now()));

  List<_Row> _seed() => [
    _Row(
      id: 'budget-groceries',
      month: _current,
      categoryId: 'cat-groceries',
      limit: const Money(70_000),
      carried: const Money(5_000),
      rollover: true,
    ),
    _Row(
      id: 'budget-restaurants',
      month: _current,
      categoryId: 'cat-restaurants',
      limit: const Money(50_000),
    ),
    _Row(
      id: 'budget-transport',
      month: _current,
      categoryId: 'cat-transport',
      limit: const Money(40_000),
    ),
  ];

  Money _spent(String categoryId, YearMonth month) {
    if (month == _current) return Money(_thisMonth[categoryId] ?? 0);
    if (month.compareTo(_current) > 0) return const Money(0);
    final swing = 85 + (month.month * 7 + categoryId.length) % 30;
    return Money((_baseSpend[categoryId] ?? 0) * swing ~/ 100);
  }

  SpendCategory _category(String id) =>
      _categories.where((category) => category.id == id).firstOrNull ??
      SpendCategory(id: id, name: id);

  BudgetMonth _view(YearMonth month) {
    final items =
        [
          for (final row in _rows.values)
            if (row.month == month)
              BudgetItem(
                id: row.id,
                category: _category(row.categoryId),
                limit: row.limit,
                carried: row.carried,
                rollover: row.rollover,
                usage: _usage(
                  row.limit + row.carried,
                  _spent(row.categoryId, month),
                ),
              ),
        ]..sort(
          (a, b) => b.usage.percent != a.usage.percent
              ? b.usage.percent - a.usage.percent
              : a.category.name.compareTo(b.category.name),
        );
    final budgeted = {for (final item in items) item.category.id};
    final unbudgeted = [
      for (final category in _categories)
        if (!budgeted.contains(category.id) &&
            _spent(category.id, month).cents > 0)
          UnbudgetedSpend(
            category: category,
            spent: _spent(category.id, month),
          ),
    ]..sort((a, b) => b.spent.compareTo(a.spent));
    Money sum(Money Function(BudgetItem item) pick) =>
        items.fold(const Money(0), (total, item) => total + pick(item));
    return BudgetMonth(
      month: month,
      total: _usage(
        sum((item) => item.usage.available),
        sum((item) => item.usage.spent),
      ),
      items: items,
      unbudgeted: unbudgeted,
    );
  }

  @override
  Future<Result<BudgetMonth>> month(YearMonth month) async {
    await Future<void>.delayed(latency);
    return Ok(_view(month));
  }

  @override
  Future<Result<BudgetMonth>> create(
    YearMonth month,
    String categoryId,
    Money limit, {
    bool rollover = false,
  }) async {
    await Future<void>.delayed(latency);
    final taken = _rows.values.any(
      (row) => row.month == month && row.categoryId == categoryId,
    );
    if (taken) {
      return const Err(ValidationFailure('Essa categoria já tem orçamento.'));
    }
    final id = 'budget-new-${++_counter}';
    _rows[id] = _Row(
      id: id,
      month: month,
      categoryId: categoryId,
      limit: limit,
      rollover: rollover,
    );
    return Ok(_view(month));
  }

  @override
  Future<Result<BudgetMonth>> update(
    String id, {
    required Money limit,
    required bool rollover,
  }) async {
    await Future<void>.delayed(latency);
    final row = _rows[id];
    if (row == null) return const Err(NotFoundFailure());
    row
      ..limit = limit
      ..rollover = rollover;
    return Ok(_view(row.month));
  }

  @override
  Future<Result<BudgetMonth>> delete(String id) async {
    await Future<void>.delayed(latency);
    final row = _rows.remove(id);
    if (row == null) return const Err(NotFoundFailure());
    return Ok(_view(row.month));
  }

  @override
  Future<Result<BudgetMonth>> copyToNext(YearMonth from) async {
    await Future<void>.delayed(latency);
    final next = from.add(1);
    final taken = {
      for (final row in _rows.values)
        if (row.month == next) row.categoryId,
    };
    final copies = [
      for (final row in _rows.values)
        if (row.month == from && !taken.contains(row.categoryId)) row,
    ];
    for (final row in copies) {
      final left = row.limit + row.carried - _spent(row.categoryId, from);
      final id = 'budget-copy-${++_counter}';
      _rows[id] = _Row(
        id: id,
        month: next,
        categoryId: row.categoryId,
        limit: row.limit,
        carried: row.rollover && left.cents > 0 ? left : const Money(0),
        rollover: row.rollover,
      );
    }
    return Ok(_view(next));
  }

  @override
  Future<Result<BudgetSuggestions>> suggestions(YearMonth month) async {
    await Future<void>.delayed(latency);
    final basedOn = [for (var back = 3; back > 0; back--) _current.add(-back)];
    final current = {
      for (final row in _rows.values)
        if (row.month == month) row.categoryId: row.limit,
    };
    final items = [
      for (final category in _categories)
        _suggestion(category, basedOn, current[category.id]),
    ]..sort((a, b) => b.suggested.compareTo(a.suggested));
    return Ok(BudgetSuggestions(month: month, basedOn: basedOn, items: items));
  }

  BudgetSuggestion _suggestion(
    SpendCategory category,
    List<YearMonth> basedOn,
    Money? current,
  ) {
    final months = [for (final month in basedOn) _spent(category.id, month)];
    final sorted = [...months]..sort();
    return BudgetSuggestion(
      category: category,
      months: months,
      suggested: Money(_friendly(sorted[sorted.length ~/ 2].cents)),
      current: current,
    );
  }

  @override
  Future<Result<BudgetMonth>> accept(
    YearMonth month,
    List<BudgetLimit> limits,
  ) async {
    await Future<void>.delayed(latency);
    for (final entry in limits) {
      final existing = _rows.values
          .where(
            (row) => row.month == month && row.categoryId == entry.categoryId,
          )
          .firstOrNull;
      if (existing != null) {
        existing.limit = entry.limit;
        continue;
      }
      final id = 'budget-new-${++_counter}';
      _rows[id] = _Row(
        id: id,
        month: month,
        categoryId: entry.categoryId,
        limit: entry.limit,
      );
    }
    return Ok(_view(month));
  }
}
