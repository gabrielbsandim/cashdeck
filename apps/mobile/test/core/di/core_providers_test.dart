import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds Dio from the config and the system clock', () {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://x.test'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(dioProvider).options.baseUrl, 'https://x.test');
    expect(container.read(clockProvider), isA<SystemClock>());
  });
}
