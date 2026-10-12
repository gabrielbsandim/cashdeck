import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/features/goals/presentation/goal_detail_screen.dart';
import 'package:cashdeck/features/goals/presentation/goals_screen.dart';
import 'package:go_router/go_router.dart';

final List<RouteBase> goalRoutes = [
  GoRoute(
    path: AppRoutes.goals,
    builder: (_, _) => const GoalsScreen(),
    routes: [
      GoRoute(
        path: ':goalId',
        builder: (_, state) =>
            GoalDetailScreen(goalId: state.pathParameters['goalId']!),
      ),
    ],
  ),
];
