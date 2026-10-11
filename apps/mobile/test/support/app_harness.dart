import 'package:cashdeck/app/app.dart';
import 'package:cashdeck/app/router/app_router.dart';
import 'package:cashdeck/core/config/app_version.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'builders.dart';
import 'pump_app.dart';

/// A fictional build, so no test reaches the platform channel.
const testVersion = '1.2.0 (7)';

/// The whole app on the fake backend at [testNow], opened at [location].
Future<ProviderContainer> pumpRoute(
  WidgetTester tester,
  String location, {
  List<Override> overrides = const [],
  Object? extra,
  double screenHeight = 2000,
}) async {
  final dispatcher = tester.binding.platformDispatcher;
  dispatcher.localesTestValue = const [Locale('pt', 'BR')];
  addTearDown(dispatcher.clearLocalesTestValue);
  tester.useTallScreen(height: screenHeight);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(FixedClock(testNow)),
        appVersionProvider.overrideWith((ref) async => testVersion),
        ...overrides,
      ],
      child: const CashdeckApp(),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(CashdeckApp)),
  );
  final router = container.read(appRouterProvider);
  await settle(tester);
  if (location != router.state.uri.path || extra != null) {
    router.go(location, extra: extra);
    await settle(tester);
  }
  return container;
}

/// Lets the fake repositories answer: their latency is a timer, which
/// pumpAndSettle alone does not wait for while nothing animates.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  for (var round = 0; round < 2; round++) {
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
  }
}

extension RouterOf on ProviderContainer {
  GoRouter get router => read(appRouterProvider);

  String get location => router.state.uri.path;
}

/// Lets a toast run out on its own, as when the user ignores it.
Future<void> waitForToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await settle(tester);
}

/// Picks [scope] in the entity chip of the tab header.
Future<void> pickScope(WidgetTester tester, EntityScope scope) async {
  await tester.tap(find.byKey(EntityChip.chipKey));
  await settle(tester);
  await tester.tap(find.byKey(EntityChip.optionKey(scope)));
  await settle(tester);
}
