import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/recap/data/recap_dtos.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:flutter_test/flutter_test.dart';

import '../recap_builders.dart';

void main() {
  test('the last closed month is the one before today', () {
    expect(
      lastClosedMonth(const CalendarDate(2026, 10, 1)),
      const YearMonth(2026, 9),
    );
    expect(
      lastClosedMonth(const CalendarDate(2027, 1, 15)),
      const YearMonth(2026, 12),
    );
  });

  test('a month with every figure plays every page', () {
    final recap = monthlyRecapFromJson(recapJson());
    expect(recap.hasChanges, isTrue);
    expect(recap.pages, RecapPage.values);
  });

  test('a bare month plays only the money and the closing words', () {
    final recap = plainRecap();
    expect(recap.hasChanges, isFalse);
    expect(recap.pages, [RecapPage.flow, RecapPage.story]);
  });

  test('any moved category or subscription makes a changes page', () {
    const subscription = RecapSubscription(name: 'Plus', amount: Money(990));
    const category = RecapCategory(
      categoryId: 'food',
      name: 'Food',
      total: Money(100),
    );
    MonthlyRecap withChanges({
      List<RecapCategory> rose = const [],
      List<RecapCategory> fell = const [],
      List<RecapSubscription> started = const [],
      List<RecapSubscription> stopped = const [],
    }) => MonthlyRecap(
      month: const YearMonth(2026, 9),
      flow: plainRecap().flow,
      previousFlow: plainRecap().flow,
      expensesChange: const RecapChange(amount: Money(0)),
      story: '',
      storySource: RecapStorySource.ai,
      rose: rose,
      fell: fell,
      started: started,
      stopped: stopped,
    );
    expect(withChanges(rose: [category]).hasChanges, isTrue);
    expect(withChanges(fell: [category]).hasChanges, isTrue);
    expect(withChanges(started: [subscription]).hasChanges, isTrue);
    expect(withChanges(stopped: [subscription]).hasChanges, isTrue);
  });

  test('values compare by content', () {
    expect(
      monthlyRecapFromJson(recapJson()),
      monthlyRecapFromJson(recapJson()),
    );
    expect(plainRecap(), isNot(plainRecap(story: 'Outro texto.')));
    expect(
      const RecapNetWorth(
        total: Money(1),
        change: RecapChange(amount: Money(1)),
      ).props,
      hasLength(2),
    );
  });
}
