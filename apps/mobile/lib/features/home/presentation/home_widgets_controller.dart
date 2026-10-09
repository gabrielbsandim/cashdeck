import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The tiles of the Início summary grid.
enum HomeWidget {
  cardBill,
  installments,
  subscriptions,
  creditUsed,
  billsDue,
  reserve,
}

final class HomeWidgetsLayout extends Equatable {
  const new({required this.order, this.hidden = const {}});

  final List<HomeWidget> order;
  final Set<HomeWidget> hidden;

  List<HomeWidget> get visible => [
    for (final widget in order)
      if (!hidden.contains(widget)) widget,
  ];

  @override
  List<Object?> get props => [order, hidden];
}

/// The order and visibility of the summary tiles on this device. A tile a
/// newer build adds shows at the end until the user moves it.
class HomeWidgetsController extends Notifier<HomeWidgetsLayout> {
  static const orderKey = 'home_widgets_order';
  static const hiddenKey = 'home_widgets_hidden';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  static List<HomeWidget> _read(String? saved) => [
    for (final name in (saved ?? '').split(','))
      ?HomeWidget.values.where((widget) => widget.name == name).firstOrNull,
  ];

  @override
  HomeWidgetsLayout build() {
    final saved = _read(_store.getString(orderKey));
    return HomeWidgetsLayout(
      order: [
        ...saved,
        for (final widget in HomeWidget.values)
          if (!saved.contains(widget)) widget,
      ],
      hidden: _read(_store.getString(hiddenKey)).toSet(),
    );
  }

  /// Moves the tile at [from] so it ends at [to] in the new order.
  void move(int from, int to) {
    final order = [...state.order];
    final widget = order.removeAt(from);
    order.insert(to, widget);
    _save(HomeWidgetsLayout(order: order, hidden: state.hidden));
  }

  void toggle(HomeWidget widget) {
    final hidden = {...state.hidden};
    if (!hidden.remove(widget)) hidden.add(widget);
    _save(HomeWidgetsLayout(order: state.order, hidden: hidden));
  }

  void _save(HomeWidgetsLayout layout) {
    state = layout;
    _store
      ..setString(
        orderKey,
        layout.order.map((widget) => widget.name).join(','),
      ).ignore()
      ..setString(
        hiddenKey,
        layout.hidden.map((widget) => widget.name).join(','),
      ).ignore();
  }
}

final homeWidgetsProvider =
    NotifierProvider<HomeWidgetsController, HomeWidgetsLayout>(
      HomeWidgetsController.new,
    );
