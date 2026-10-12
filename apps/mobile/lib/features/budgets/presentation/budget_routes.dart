import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/budgets/presentation/budget_suggestions_screen.dart';
import 'package:cashdeck/features/budgets/presentation/budgets_controller.dart';
import 'package:cashdeck/features/budgets/presentation/budgets_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The `?month=YYYY-MM` of a budget link; a missing or broken one is null.
YearMonth? monthQuery(GoRouterState state) {
  final raw = state.uri.queryParameters['month'];
  if (raw == null) return null;
  try {
    return YearMonth.parse(raw);
  } on FormatException {
    return null;
  }
}

final List<RouteBase> budgetRoutes = [
  GoRoute(
    path: AppRoutes.budgets,
    builder: (_, state) => BudgetsScreen(initialMonth: monthQuery(state)),
    routes: [
      GoRoute(
        path: 'suggestions',
        builder: (_, state) => Consumer(
          builder: (_, ref, _) => BudgetSuggestionsScreen(
            month: monthQuery(state) ?? ref.read(currentBudgetMonthProvider),
          ),
        ),
      ),
    ],
  ),
];
