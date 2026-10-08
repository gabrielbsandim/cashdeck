import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pump_app.dart';

void main() {
  testWidgets('switches the scope the screens read', (tester) async {
    await tester.pumpApp(const EntitySwitcher());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EntitySwitcher)),
    );
    expect(find.text(l10n.entityPersonal), findsOneWidget);
    expect(find.text(l10n.entityCompany), findsOneWidget);
    expect(find.text(l10n.entityConsolidated), findsOneWidget);
    expect(container.read(entityScopeProvider), EntityScope.personal);

    await tester.tap(
      find.byKey(EntitySwitcher.segmentKey(EntityScope.consolidated)),
    );
    await tester.pump();

    expect(container.read(entityScopeProvider), EntityScope.consolidated);
  });

  testWidgets('the app bar chip changes the scope from a sheet', (
    tester,
  ) async {
    await tester.pumpApp(
      const Column(
        children: [
          EntityChip(),
          EntityKindBadge(kind: EntityKind.personal),
          EntityKindBadge(kind: EntityKind.company),
        ],
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(EntityChip)),
    );

    await tester.tap(find.byKey(EntityChip.chipKey));
    await tester.pumpAndSettle();
    expect(find.text(l10n.entitySheetTitle), findsOneWidget);
    await tester.tap(find.byKey(EntityChip.optionKey(EntityScope.company)));
    await tester.pumpAndSettle();

    expect(container.read(entityScopeProvider), EntityScope.company);
    expect(find.text(l10n.entitySheetTitle), findsNothing);
    expect(find.text(l10n.entityCompanyShort), findsNWidgets(2));
  });

  test('selecting the current scope keeps the state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(entityScopeProvider.notifier);
    var notified = 0;
    container.listen(entityScopeProvider, (_, _) => notified++);

    controller
      ..select(EntityScope.personal)
      ..select(EntityScope.company);

    expect(notified, 1);
  });
}
