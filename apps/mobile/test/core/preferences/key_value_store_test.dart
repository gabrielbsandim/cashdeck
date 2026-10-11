import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('keeps strings and booleans in memory', () async {
    final store = InMemoryKeyValueStore({'a': 1});
    expect(store.getString('a'), isNull);
    expect(store.getBool('a'), isNull);

    await store.setString('s', 'x');
    await store.setBool('b', value: true);

    expect(store.getString('s'), 'x');
    expect(store.getBool('b'), isTrue);
  });

  test('reads and writes the shared preferences', () async {
    SharedPreferences.setMockInitialValues({'s': 'x'});
    final store = SharedPreferencesStore(await SharedPreferences.getInstance());

    expect(store.getString('s'), 'x');
    await store.setBool('b', value: false);
    await store.setString('t', 'y');

    expect(store.getBool('b'), isFalse);
    expect(store.getString('t'), 'y');
  });

  test('the display preferences survive a restart', () {
    final store = InMemoryKeyValueStore();
    ProviderContainer launch() {
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    launch().read(displayPreferencesProvider.notifier).toggleHideAmounts();

    expect(
      launch().read(displayPreferencesProvider),
      const DisplayPreferences(hideAmounts: true),
    );
  });
}
