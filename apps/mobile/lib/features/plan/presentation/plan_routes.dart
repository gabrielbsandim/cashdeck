import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/features/plan/presentation/plan_screen.dart';
import 'package:go_router/go_router.dart';

final List<RouteBase> planRoutes = [
  GoRoute(path: AppRoutes.plan, builder: (_, _) => const PlanScreen()),
];
