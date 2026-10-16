import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/features/card_notifications/card_notifications_providers.dart';
import 'package:cashdeck/features/card_notifications/data/fake_card_notification_bridge.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_harness.dart';

void main() {
  testWidgets('the app hands each session to forwarding left on', (
    tester,
  ) async {
    final bridge = FakeCardNotificationBridge(access: true);
    await bridge.configure(
      const CardNotificationConfig(
        enabled: true,
        routes: {'com.example.cardapp': 'card'},
        baseUrl: 'https://cashdeck.example.com',
        token: 'replaced',
      ),
    );
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [cardNotificationBridgeProvider.overrideWithValue(bridge)],
    );
    expect(bridge.config.token, ServerCredentials.demo.token);

    final session = app.read(serverSessionProvider.notifier);
    await session.signOut();
    await settle(tester);
    expect(bridge.config.token, ServerCredentials.demo.token);

    const next = ServerCredentials(
      baseUrl: 'https://cashdeck.example.com',
      token: 'next',
    );
    await session.signIn(next);
    await settle(tester);
    expect(bridge.config.token, 'next');
    expect(bridge.config.routes, {'com.example.cardapp': 'card'});
  });
}
