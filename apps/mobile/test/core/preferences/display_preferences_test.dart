import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts with amounts visible', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(displayPreferencesProvider),
      const DisplayPreferences(),
    );
  });

  test('toggles the privacy mode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(displayPreferencesProvider.notifier).toggleHideAmounts();

    expect(
      container.read(displayPreferencesProvider),
      const DisplayPreferences(hideAmounts: true),
    );
  });
}
