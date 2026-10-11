import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether amounts show on this device; the theme follows the system.
final class DisplayPreferences extends Equatable {
  const new({this.hideAmounts = false});

  final bool hideAmounts;

  @override
  List<Object?> get props => [hideAmounts];
}

/// Reads the saved choice at start and writes every change back.
class DisplayPreferencesController extends Notifier<DisplayPreferences> {
  static const hideAmountsKey = 'hide_amounts';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  DisplayPreferences build() {
    return DisplayPreferences(
      hideAmounts: _store.getBool(hideAmountsKey) ?? false,
    );
  }

  void toggleHideAmounts() {
    state = DisplayPreferences(hideAmounts: !state.hideAmounts);
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
