import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';

import '../loans/loan_builders.dart' show moneyJson;

Map<String, Object?> planGoalJson({
  String id = 'g1',
  String kind = 'PURCHASE',
  String status = 'PLANNED',
  String? month = '2027-05',
  int cash = 5_000_000,
  List<Map<String, Object?>> delays = const [],
  String? metric,
}) => {
  'id': id,
  'kind': kind,
  'name': 'Carro',
  'icon': null,
  'status': status,
  'month': month,
  'cash': moneyJson(cash),
  'delays': delays,
  'price': kind == 'PURCHASE' ? moneyJson(9_000_000) : null,
  'tradeIn': kind == 'PURCHASE' ? moneyJson(4_000_000) : null,
  'tradeInAssetId': null,
  'tradeInAssetName': null,
  'financed': kind == 'PURCHASE' ? moneyJson(0) : null,
  'monthlyCost': kind == 'PURCHASE' ? moneyJson(0) : null,
  'keepsValue': kind == 'PURCHASE',
  'payment': kind == 'PURCHASE' ? 'CARD' : null,
  'installments': kind == 'PURCHASE' ? 10 : null,
  'goalId': kind == 'PURCHASE' ? 'goal-car' : null,
  'notBefore': null,
  'by': kind == 'PURCHASE' ? '2028-01' : null,
  'yearly': kind == 'YEARLY' ? moneyJson(1_200_000) : null,
  'metric': metric,
  'target': metric == null ? null : moneyJson(100_000_000),
  'current': metric == null ? null : moneyJson(40_000_000),
};

Map<String, Object?> lifePlanJson({
  List<Map<String, Object?>>? goals,
  bool fromBudget = true,
}) => {
  'asOf': '2026-10',
  'monthlySavings': moneyJson(2_000_000),
  'savingsFromBudget': fromBudget,
  'monthlySpending': moneyJson(2_000_000),
  'reserveMonths': 6,
  'reserve': moneyJson(12_000_000),
  'yearlyYield': 5.5,
  'keepInvested': 50,
  'netWorth': moneyJson(60_000_000),
  'invested': moneyJson(30_000_000),
  'yearlyProvision': moneyJson(100_000),
  'free': moneyJson(1_900_000),
  'goals': goals ?? [planGoalJson()],
  'timeline': [
    {
      'month': '2026-10',
      'netWorth': moneyJson(60_000_000),
      'invested': moneyJson(30_000_000),
    },
    {
      'month': '2027-10',
      'netWorth': moneyJson(84_000_000),
      'invested': moneyJson(54_000_000),
    },
  ],
};

const testPlanGoal = PlanGoal(
  id: 'g1',
  kind: PlanGoalKind.purchase,
  name: 'Carro',
  status: PlanStatus.planned,
  month: YearMonth(2027, 5),
  cash: Money(5_000_000),
  price: Money(9_000_000),
  tradeIn: Money(4_000_000),
  financed: Money(0),
  monthlyCost: Money(0),
  keepsValue: true,
  payment: PlanPayment.card,
  installments: 10,
  goalId: 'goal-car',
  by: YearMonth(2028, 1),
);
