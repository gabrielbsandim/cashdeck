import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';

/// A fictional month, the same every time it is asked for, so the story
/// viewer has something to play offline.
final class FakeRecapRepository implements RecapRepository {
  const new({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;

  static const Map<String, String> _stories = {
    'pt':
        'Entrou mais do que saiu e o mês fechou no azul. Mercado segue sendo o '
        'maior gasto, mas lazer caiu bastante. Vale manter o ritmo.',
    'en':
        'More came in than went out and the month closed in the black. '
        'Groceries is still the biggest expense, but leisure fell a lot. '
        'Worth keeping the pace.',
  };

  @override
  Future<Result<MonthlyRecap>> get(
    YearMonth month, {
    required String locale,
  }) async {
    await Future<void>.delayed(latency);
    return Ok(
      MonthlyRecap(
        month: month,
        flow: const RecapFlow(
          income: Money(850_000),
          expenses: Money(612_340),
          net: Money(237_660),
        ),
        previousFlow: const RecapFlow(
          income: Money(850_000),
          expenses: Money(655_900),
          net: Money(194_100),
        ),
        expensesChange: const RecapChange(amount: Money(-43_560), percent: -7),
        savingsPercent: 28,
        previousSavingsPercent: 23,
        topCategory: const RecapCategory(
          categoryId: 'cat-groceries',
          key: 'groceries',
          name: 'Groceries',
          total: Money(184_250),
          sharePercent: 30,
        ),
        rose: const [
          RecapCategory(
            categoryId: 'cat-transport',
            key: 'transport',
            name: 'Transport',
            total: Money(52_300),
            change: RecapChange(amount: Money(18_900), percent: 57),
          ),
        ],
        fell: const [
          RecapCategory(
            categoryId: 'cat-leisure',
            key: 'leisure',
            name: 'Leisure',
            total: Money(31_000),
            change: RecapChange(amount: Money(-64_200), percent: -67),
          ),
        ],
        started: const [
          RecapSubscription(name: 'Cine Nuvem', amount: Money(3_990)),
        ],
        netWorth: const RecapNetWorth(
          total: Money(9_830_400),
          change: RecapChange(amount: Money(261_300), percent: 3),
        ),
        story: _stories[locale] ?? _stories['pt']!,
        storySource: RecapStorySource.ai,
      ),
    );
  }
}
