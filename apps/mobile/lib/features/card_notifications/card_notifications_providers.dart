import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/features/card_notifications/application/card_notification_use_cases.dart';
import 'package:cashdeck/features/card_notifications/data/fake_card_notification_bridge.dart';
import 'package:cashdeck/features/card_notifications/data/platform_card_notification_bridge.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cardNotificationBridgeProvider = Provider<CardNotificationBridge>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeCardNotificationBridge(),
    Backend.api => PlatformCardNotificationBridge(
      supported: defaultTargetPlatform == TargetPlatform.android,
    ),
  };
});

final listNotificationCardsProvider = Provider<ListNotificationCards>(
  (ref) => ListNotificationCards(ref.watch(transactionsRepositoryProvider)),
);

final saveCardNotificationsProvider = Provider<SaveCardNotifications>(
  (ref) => SaveCardNotifications(ref.watch(cardNotificationBridgeProvider)),
);

final stopCardNotificationsProvider = Provider<StopCardNotifications>(
  (ref) => StopCardNotifications(ref.watch(cardNotificationBridgeProvider)),
);
