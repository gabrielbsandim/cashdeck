import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:equatable/equatable.dart';

/// Below 80% of the limit, from 80%, and from 100%.
enum BudgetLevel { ok, near, reached }

/// A category as a budget names it; [key] marks a built-in one the app
/// translates.
final class SpendCategory extends Equatable {
  const new({required this.id, required this.name, this.key});

  final String id;
  final String? key;
  final String name;

  @override
  List<Object?> get props => [id, key, name];
}

/// Spent against what a month allows, in total or for one category.
final class BudgetUsage extends Equatable {
  const new({
    required this.available,
    required this.spent,
    required this.remaining,
    required this.percent,
    required this.level,
  });

  /// The limit plus what a rollover carried from the month before.
  final Money available;
  final Money spent;

  /// Negative past the limit.
  final Money remaining;
  final int percent;
  final BudgetLevel level;

  bool get over => remaining.isNegative;

  @override
  List<Object?> get props => [available, spent, remaining, percent, level];
}

final class BudgetItem extends Equatable {
  const new({
    required this.id,
    required this.category,
    required this.limit,
    required this.carried,
    required this.rollover,
    required this.usage,
  });

  final String id;
  final SpendCategory category;
  final Money limit;
  final Money carried;

  /// Whether the leftover moves to the next month when it is copied.
  final bool rollover;
  final BudgetUsage usage;

  @override
  List<Object?> get props => [id, category, limit, carried, rollover, usage];
}

/// A category with spending this month and no budget yet.
final class UnbudgetedSpend extends Equatable {
  const new({required this.category, required this.spent});

  final SpendCategory category;
  final Money spent;

  @override
  List<Object?> get props => [category, spent];
}

final class BudgetMonth extends Equatable {
  const new({
    required this.month,
    required this.total,
    required this.items,
    this.unbudgeted = const [],
  });

  final YearMonth month;
  final BudgetUsage total;

  /// Fullest first.
  final List<BudgetItem> items;

  /// Biggest spend first.
  final List<UnbudgetedSpend> unbudgeted;

  bool get isEmpty => items.isEmpty;

  /// The categories at or past 80%, fullest first, at most [count].
  List<BudgetItem> nearLimit({int count = 3}) => items
      .where((item) => item.usage.level != BudgetLevel.ok)
      .take(count)
      .toList();

  @override
  List<Object?> get props => [month, total, items, unbudgeted];
}

/// The median of the last complete months, rounded to a friendly value.
final class BudgetSuggestion extends Equatable {
  const new({
    required this.category,
    required this.months,
    required this.suggested,
    this.current,
  });

  final SpendCategory category;

  /// Oldest first, one per month the suggestion read.
  final List<Money> months;
  final Money suggested;

  /// The limit already set this month, if any.
  final Money? current;

  @override
  List<Object?> get props => [category, months, suggested, current];
}

final class BudgetSuggestions extends Equatable {
  const new({required this.month, required this.basedOn, required this.items});

  final YearMonth month;
  final List<YearMonth> basedOn;
  final List<BudgetSuggestion> items;

  @override
  List<Object?> get props => [month, basedOn, items];
}

/// A limit the user accepted or adjusted, per category.
typedef BudgetLimit = ({String categoryId, Money limit});

/// The limits the suggestion screen sends: one per [chosen] category, with
/// the adjusted value when the user changed it. A zero leaves it out.
List<BudgetLimit> chosenLimits(
  BudgetSuggestions suggestions, {
  required Set<String> chosen,
  Map<String, Money> adjusted = const {},
}) => [
  for (final item in suggestions.items)
    if (chosen.contains(item.category.id))
      (
        categoryId: item.category.id,
        limit: adjusted[item.category.id] ?? item.suggested,
      ),
].where((entry) => entry.limit.cents > 0).toList();

abstract interface class BudgetsRepository {
  Future<Result<BudgetMonth>> month(YearMonth month);

  Future<Result<BudgetMonth>> create(
    YearMonth month,
    String categoryId,
    Money limit, {
    bool rollover = false,
  });

  Future<Result<BudgetMonth>> update(
    String id, {
    required Money limit,
    required bool rollover,
  });

  Future<Result<BudgetMonth>> delete(String id);

  /// Copies [from] into the month after, carrying the leftover of the
  /// budgets that roll over.
  Future<Result<BudgetMonth>> copyToNext(YearMonth from);

  Future<Result<BudgetSuggestions>> suggestions(YearMonth month);

  Future<Result<BudgetMonth>> accept(YearMonth month, List<BudgetLimit> limits);
}
