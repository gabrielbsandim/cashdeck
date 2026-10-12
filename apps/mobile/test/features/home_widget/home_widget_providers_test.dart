import 'package:cashdeck/features/home_widget/data/platform_home_widget_publisher.dart';
import 'package:cashdeck/features/home_widget/home_widget_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only Android gets the platform widget', () {
    expect(
      homeWidgetPublisherFor(android: true),
      isA<PlatformHomeWidgetPublisher>(),
    );
    expect(
      homeWidgetPublisherFor(android: false),
      isA<NoHomeWidgetPublisher>(),
    );
  });

  test('the test host has no widget', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(homeWidgetPublisherProvider),
      isA<NoHomeWidgetPublisher>(),
    );
  });
}
