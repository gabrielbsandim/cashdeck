import 'dart:io';

import 'package:cashdeck/features/home_widget/application/home_widget_use_cases.dart';
import 'package:cashdeck/features/home_widget/data/platform_home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/domain/home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/home_widget_background.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Only Android has the widget; iOS would need a WidgetKit extension.
HomeWidgetPublisher homeWidgetPublisherFor({required bool android}) => android
    ? const PlatformHomeWidgetPublisher(refreshHomeWidgetInBackground)
    : const NoHomeWidgetPublisher();

/// Whether this platform has the widget, so its settings show.
final homeWidgetAvailableProvider = Provider<bool>((ref) => Platform.isAndroid);

final homeWidgetPublisherProvider = Provider<HomeWidgetPublisher>(
  (ref) => homeWidgetPublisherFor(android: Platform.isAndroid),
);

final publishHomeWidgetProvider = Provider<PublishHomeWidget>(
  (ref) => PublishHomeWidget(ref.watch(homeWidgetPublisherProvider)),
);

final clearHomeWidgetProvider = Provider<ClearHomeWidget>(
  (ref) => ClearHomeWidget(ref.watch(homeWidgetPublisherProvider)),
);

final enableHomeWidgetRefreshProvider = Provider<EnableHomeWidgetRefresh>(
  (ref) => EnableHomeWidgetRefresh(ref.watch(homeWidgetPublisherProvider)),
);
