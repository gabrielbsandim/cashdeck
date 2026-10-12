import 'dart:convert';

import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/home_widget/domain/widget_settings.dart';
import 'package:cashdeck/features/home_widget/presentation/widget_values_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/safe_mode_support.dart';

final String _zones = jsonEncode([const SafeZone(homePoint).toJson()]);

void main() {
  ProviderContainer containerWith(KeyValueStore store) {
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('shows amounts by default with no zone and no privacy mode', () {
    final container = containerWith(InMemoryKeyValueStore());

    expect(container.read(widgetValuesProvider), isNull);
    expect(container.read(widgetShowsAmountsProvider), isTrue);
  });

  test('a saved zone hides them until the user decides', () {
    final store = InMemoryKeyValueStore({SafeModeController.zonesKey: _zones});
    final container = containerWith(store);

    expect(container.read(widgetShowsAmountsProvider), isFalse);

    container.read(widgetValuesProvider.notifier).toggle();

    expect(container.read(widgetValuesProvider), isTrue);
    expect(container.read(widgetShowsAmountsProvider), isTrue);
    expect(store.getBool(WidgetValuesController.storeKey), isTrue);
  });

  test('privacy mode masks them whatever the choice', () {
    final container = containerWith(
      InMemoryKeyValueStore({WidgetValuesController.storeKey: true}),
    );

    container.read(displayPreferencesProvider.notifier).toggleHideAmounts();

    expect(container.read(widgetShowsAmountsProvider), isFalse);
  });

  test('savedWidgetSettings reads what the app saved', () {
    expect(
      savedWidgetSettings(InMemoryKeyValueStore()),
      const WidgetSettings(),
    );
    expect(
      savedWidgetSettings(
        InMemoryKeyValueStore({
          DisplayPreferencesController.hideAmountsKey: true,
          SafeModeController.zonesKey: _zones,
          WidgetValuesController.storeKey: false,
          EntityScopeController.storeKey: EntityScope.company.name,
        }),
      ),
      const WidgetSettings(
        privacyMode: true,
        hasSafeZone: true,
        choice: false,
        scope: EntityScope.company,
      ),
    );
  });
}
