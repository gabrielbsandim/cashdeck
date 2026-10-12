import 'dart:async';

import 'package:cashdeck/features/home_widget/domain/home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

/// The Android widget through the `home_widget` plugin. The widget is a
/// courtesy: a plugin failure is swallowed and never reaches a screen.
/// [background] runs in a background isolate when the widget asks for a
/// refresh; it must be a top-level function.
final class PlatformHomeWidgetPublisher implements HomeWidgetPublisher {
  const new([this.background]);

  final FutureOr<void> Function(Uri? uri)? background;

  static const provider = 'io.cashdeck.app.widget.CashdeckWidgetProvider';

  @override
  Future<void> publish(WidgetSnapshot snapshot) => _guard(() async {
    for (final MapEntry(:key, :value) in snapshot.values.entries) {
      await HomeWidget.saveWidgetData<Object>(key, value);
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: provider);
  });

  @override
  Future<void> clear() => _guard(() async {
    for (final key in WidgetKeys.all) {
      await HomeWidget.saveWidgetData<Object>(key, null, deleteFile: false);
    }
    await HomeWidget.updateWidget(qualifiedAndroidName: provider);
  });

  @override
  Future<void> enableBackgroundRefresh() => _guard(() async {
    final callback = background;
    if (callback == null) return;
    await HomeWidget.registerInteractivityCallback(callback);
  });

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}

/// iOS and the tests: no widget to feed.
final class NoHomeWidgetPublisher implements HomeWidgetPublisher {
  const new();

  @override
  Future<void> publish(WidgetSnapshot snapshot) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> enableBackgroundRefresh() async {}
}
