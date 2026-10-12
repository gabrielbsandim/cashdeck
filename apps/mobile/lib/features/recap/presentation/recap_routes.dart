import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/features/recap/presentation/recap_labels.dart';
import 'package:cashdeck/features/recap/presentation/recap_screen.dart';
import 'package:go_router/go_router.dart';

final List<RouteBase> recapRoutes = [
  GoRoute(
    path: '${AppRoutes.recaps}/:month',
    builder: (_, state) => RecapScreen(
      month: state.pathParameters['month']!,
      entity: recapEntityOf(state.uri.queryParameters['entity']),
    ),
  ),
];
