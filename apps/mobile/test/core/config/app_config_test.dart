import 'package:cashdeck/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to the fake backend and the local API', () {
    final config = AppConfig.parse(backend: '', apiBaseUrl: '');

    expect(config.backend, Backend.fake);
    expect(config.apiBaseUrl, AppConfig.defaultApiBaseUrl);
  });

  test('reads the backend and base URL from the dart-defines', () {
    final config = AppConfig.parse(
      backend: 'api',
      apiBaseUrl: 'https://cash.example',
    );

    expect(
      config,
      const AppConfig(backend: Backend.api, apiBaseUrl: 'https://cash.example'),
    );
  });

  test('fromEnvironment falls back to the defaults in tests', () {
    expect(AppConfig.fromEnvironment().backend, Backend.fake);
  });
}
