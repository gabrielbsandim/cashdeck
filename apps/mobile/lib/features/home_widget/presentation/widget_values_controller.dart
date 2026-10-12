import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/home_widget/domain/widget_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Mostrar valores no widget" as the user set it, null until they do, so the
/// default follows privacy mode and the safe zones.
class WidgetValuesController extends Notifier<bool?> {
  static const storeKey = 'widget_show_amounts';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  bool? build() => _store.getBool(storeKey);

  /// Flips what the widget shows now and keeps it as the user's choice.
  void toggle() {
    final next = !widgetShowsAmounts(
      privacyMode: ref.read(displayPreferencesProvider).hideAmounts,
      hasSafeZone: ref.read(safeModeProvider).enabled,
      choice: state,
    );
    state = next;
    _store.setBool(storeKey, value: next).ignore();
  }
}

final widgetValuesProvider = NotifierProvider<WidgetValuesController, bool?>(
  WidgetValuesController.new,
);

/// Whether the widget shows amounts. Unlike the app it ignores whether the
/// phone is inside a safe zone: the home screen cannot check it.
final widgetShowsAmountsProvider = Provider<bool>(
  (ref) => widgetShowsAmounts(
    privacyMode: ref.watch(
      displayPreferencesProvider.select((prefs) => prefs.hideAmounts),
    ),
    hasSafeZone: ref.watch(safeModeProvider.select((mode) => mode.enabled)),
    choice: ref.watch(widgetValuesProvider),
  ),
);

/// The same settings read straight from [store], for the background refresh
/// that runs without the app's providers.
WidgetSettings savedWidgetSettings(KeyValueStore store) => WidgetSettings(
  privacyMode:
      store.getBool(DisplayPreferencesController.hideAmountsKey) ?? false,
  hasSafeZone: savedSafeZones(store).isNotEmpty,
  choice: store.getBool(WidgetValuesController.storeKey),
  scope: savedEntityScope(store),
);
