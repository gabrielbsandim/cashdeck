import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';

const _flow = RecapFlow(
  income: Money(500_000),
  expenses: Money(120_000),
  net: Money(380_000),
);

/// A recap with only the figures every month has: money in and out and the
/// closing words.
MonthlyRecap plainRecap({
  RecapFlow flow = _flow,
  String story = 'Setembro foi tranquilo.',
}) => MonthlyRecap(
  month: const YearMonth(2026, 9),
  flow: flow,
  previousFlow: flow,
  expensesChange: const RecapChange(amount: Money(0), percent: 0),
  story: story,
  storySource: RecapStorySource.template,
);

Map<String, dynamic> _money(int cents) => {'cents': cents, 'currency': 'BRL'};

Map<String, dynamic> _change(int cents, int? percent) => {
  'amount': _money(cents),
  'percent': percent,
};

Map<String, dynamic> _flowJson(int income, int expenses) => {
  'income': _money(income),
  'expenses': _money(expenses),
  'net': _money(income - expenses),
};

/// The server's recap of September 2026, every figure present.
Map<String, dynamic> recapJson({String source = 'AI'}) => {
  'month': '2026-09',
  'entity': 'PF',
  'flow': _flowJson(600_000, 236_980),
  'previousFlow': _flowJson(500_000, 201_990),
  'incomeChange': _change(100_000, 20),
  'expensesChange': _change(34_990, 17),
  'savings': {'percent': 61, 'previousPercent': 60},
  'topCategory': {
    'categoryId': 'food',
    'key': 'groceries',
    'name': 'Groceries',
    'icon': null,
    'total': _money(180_000),
    'sharePercent': 76,
  },
  'changes': {
    'rose': [
      {
        'categoryId': 'fun',
        'key': null,
        'name': 'Shows',
        'icon': null,
        'total': _money(50_000),
        'previous': _money(0),
        'change': _change(50_000, null),
      },
    ],
    'fell': [
      {
        'categoryId': 'trip',
        'key': 'travel',
        'name': 'Travel',
        'icon': null,
        'total': _money(0),
        'previous': _money(90_000),
        'change': _change(-90_000, -100),
      },
    ],
  },
  'subscriptions': {
    'started': [
      {'key': 'video max', 'name': 'Video Max', 'amount': _money(2_990)},
    ],
    'stopped': [
      {'key': 'gym club', 'name': 'Gym Club', 'amount': _money(8_000)},
    ],
  },
  'netWorth': {'total': _money(1_010_000), 'change': _change(363_020, 56)},
  'story': {
    'text': r'Setembro fechou com R$ 3.630,20 de sobra.',
    'locale': 'pt',
    'source': source,
  },
  'generatedAt': '2026-10-01T15:30:00.000Z',
};
