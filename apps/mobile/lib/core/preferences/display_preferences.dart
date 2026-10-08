import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How the app looks on this device: the theme and whether amounts show.
final class DisplayPreferences extends Equatable {
  const new({this.themeMode = ThemeMode.system, this.hideAmounts = false});

  final ThemeMode themeMode;
  final bool hideAmounts;

  DisplayPreferences copyWith({ThemeMode? themeMode, bool? hideAmounts}) =>
      DisplayPreferences(
        themeMode: themeMode ?? this.themeMode,
        hideAmounts: hideAmounts ?? this.hideAmounts,
      );

  @override
  List<Object?> get props => [themeMode, hideAmounts];
}

/// Reads the saved choice at start and writes every change back.
class DisplayPreferencesController extends Notifier<DisplayPreferences> {
  static const themeKey = 'theme_mode';
  static const hideAmountsKey = 'hide_amounts';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  DisplayPreferences build() {
    final theme = _store.getString(themeKey);
    return DisplayPreferences(
      themeMode:
          ThemeMode.values.where((mode) => mode.name == theme).firstOrNull ??
          ThemeMode.system,
      hideAmounts: _store.getBool(hideAmountsKey) ?? false,
    );
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _store.setString(themeKey, mode.name).ignore();
  }

  void toggleHideAmounts() {
    state = state.copyWith(hideAmounts: !state.hideAmounts);
    _store.setBool(hideAmountsKey, value: state.hideAmounts).ignore();
  }
}

final displayPreferencesProvider =
    NotifierProvider<DisplayPreferencesController, DisplayPreferences>(
      DisplayPreferencesController.new,
    );

/// Whether amounts are masked right now; every amount, alert and chart label
/// built from money reads this.
final hideAmountsProvider = Provider<bool>(
  (ref) => ref.watch(
    displayPreferencesProvider.select((prefs) => prefs.hideAmounts),
  ),
);
