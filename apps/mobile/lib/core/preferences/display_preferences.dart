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

class DisplayPreferencesController extends Notifier<DisplayPreferences> {
  @override
  DisplayPreferences build() => const DisplayPreferences();

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);

  void toggleHideAmounts() =>
      state = state.copyWith(hideAmounts: !state.hideAmounts);
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
