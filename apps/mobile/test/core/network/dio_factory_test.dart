import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/network/dio_factory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('points at the configured API and sends JSON', () {
    final dio = createApiDio(
      const AppConfig(backend: Backend.api, apiBaseUrl: 'https://x.test'),
    );

    expect(dio.options.baseUrl, 'https://x.test');
    expect(dio.options.headers['X-Client'], 'mobile');
    expect(dio.options.contentType, contains('application/json'));
  });
}
