import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';

/// The home screen widget outside the app. A platform without one ignores
/// every call.
abstract interface class HomeWidgetPublisher {
  /// Saves the values of [snapshot] and redraws the widget.
  Future<void> publish(WidgetSnapshot snapshot);

  /// Forgets every value, so a signed-out phone shows no numbers.
  Future<void> clear();

  /// Lets the platform wake the app to refresh the widget while it is
  /// closed.
  Future<void> enableBackgroundRefresh();
}
