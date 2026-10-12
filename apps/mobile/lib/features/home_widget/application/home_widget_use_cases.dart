import 'package:cashdeck/features/home_widget/domain/home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';

/// Hands what Início loaded to the home screen widget.
final class PublishHomeWidget {
  const new(this._publisher);

  final HomeWidgetPublisher _publisher;

  Future<void> call(WidgetSnapshot snapshot) => _publisher.publish(snapshot);
}

/// Empties the widget once the session ends.
final class ClearHomeWidget {
  const new(this._publisher);

  final HomeWidgetPublisher _publisher;

  Future<void> call() => _publisher.clear();
}

/// Lets the platform run the background refresh while the app is closed.
final class EnableHomeWidgetRefresh {
  const new(this._publisher);

  final HomeWidgetPublisher _publisher;

  Future<void> call() => _publisher.enableBackgroundRefresh();
}
