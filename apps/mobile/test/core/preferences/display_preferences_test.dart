import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts on the system theme with amounts visible', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(displayPreferencesProvider),
      const DisplayPreferences(),
    );
  });

  test('changes the theme and toggles the privacy mode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(displayPreferencesProvider.notifier);

    controller
      ..setThemeMode(ThemeMode.dark)
      ..toggleHideAmounts();

    expect(
      container.read(displayPreferencesProvider),
      const DisplayPreferences(themeMode: ThemeMode.dark, hideAmounts: true),
    );
  });
}
