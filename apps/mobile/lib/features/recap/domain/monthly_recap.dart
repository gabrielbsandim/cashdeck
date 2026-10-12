import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:equatable/equatable.dart';

/// An amount against the month before; [percent] is null without a base.
final class RecapChange extends Equatable {
  const new({required this.amount, this.percent});

  final Money amount;
  final int? percent;

  @override
  List<Object?> get props => [amount, percent];
}

final class RecapFlow extends Equatable {
  const new({required this.income, required this.expenses, required this.net});

  final Money income;
  final Money expenses;

  /// Negative when more went out than came in.
  final Money net;

  @override
  List<Object?> get props => [income, expenses, net];
}

final class RecapCategory extends Equatable {
  const new({
    required this.categoryId,
    required this.name,
    required this.total,
    this.key,
    this.sharePercent,
    this.change,
  });

  final String categoryId;

  /// The built-in category key, which the app names in its own language.
  final String? key;
  final String name;
  final Money total;

  /// Of everything spent in the month; only on the top category.
  final int? sharePercent;

  /// Against the month before; only on a category that moved.
  final RecapChange? change;

  @override
  List<Object?> get props => [
    categoryId,
    key,
    name,
    total,
    sharePercent,
    change,
  ];
}

final class RecapSubscription extends Equatable {
  const new({required this.name, required this.amount});

  final String name;
  final Money amount;

  @override
  List<Object?> get props => [name, amount];
}

final class RecapNetWorth extends Equatable {
  const new({required this.total, required this.change});

  final Money total;
  final RecapChange change;

  @override
  List<Object?> get props => [total, change];
}

/// Who wrote the closing words: the AI from the figures, or the fixed
/// template that stands in when it could not.
enum RecapStorySource { ai, template }

/// One page of the story viewer, in the order they play.
enum RecapPage { flow, topCategory, changes, savings, netWorth, story }

/// A month that closed, told in figures the server computed.
final class MonthlyRecap extends Equatable {
  const new({
    required this.month,
    required this.flow,
    required this.previousFlow,
    required this.expensesChange,
    required this.story,
    required this.storySource,
    this.savingsPercent,
    this.previousSavingsPercent,
    this.topCategory,
    this.rose = const [],
    this.fell = const [],
    this.started = const [],
    this.stopped = const [],
    this.netWorth,
  });

  final YearMonth month;
  final RecapFlow flow;
  final RecapFlow previousFlow;
  final RecapChange expensesChange;
  final int? savingsPercent;
  final int? previousSavingsPercent;
  final RecapCategory? topCategory;
  final List<RecapCategory> rose;
  final List<RecapCategory> fell;
  final List<RecapSubscription> started;
  final List<RecapSubscription> stopped;
  final RecapNetWorth? netWorth;
  final String story;
  final RecapStorySource storySource;

  bool get hasChanges =>
      rose.isNotEmpty ||
      fell.isNotEmpty ||
      started.isNotEmpty ||
      stopped.isNotEmpty;

  /// The pages worth showing: a figure the month does not have is skipped.
  List<RecapPage> get pages => [
    RecapPage.flow,
    if (topCategory != null) RecapPage.topCategory,
    if (hasChanges) RecapPage.changes,
    if (savingsPercent != null) RecapPage.savings,
    if (netWorth != null) RecapPage.netWorth,
    RecapPage.story,
  ];

  @override
  List<Object?> get props => [
    month,
    flow,
    previousFlow,
    expensesChange,
    savingsPercent,
    previousSavingsPercent,
    topCategory,
    rose,
    fell,
    started,
    stopped,
    netWorth,
    story,
    storySource,
  ];
}

/// The month a recap covers on [today]: the last one that closed.
YearMonth lastClosedMonth(CalendarDate today) => YearMonth.of(today).add(-1);

abstract interface class RecapRepository {
  /// [locale] is `pt` or `en`, the language of the closing words.
  Future<Result<MonthlyRecap>> get(YearMonth month, {required String locale});
}
