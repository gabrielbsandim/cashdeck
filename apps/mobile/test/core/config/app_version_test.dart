import 'package:cashdeck/core/config/app_version.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('reads the version and build number of the installed app', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Cashdeck',
      packageName: 'io.cashdeck.app',
      version: '0.3.1',
      buildNumber: '12',
      buildSignature: '',
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(appVersionProvider.future), '0.3.1 (12)');
  });
}
