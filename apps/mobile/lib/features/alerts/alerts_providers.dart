import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:cashdeck/features/alerts/application/register_push_device.dart';
import 'package:cashdeck/features/alerts/data/api_alerts_repository.dart';
import 'package:cashdeck/features/alerts/data/fake_alerts_repository.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  return switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => FakeAlertsRepository(ref.watch(clockProvider)),
    Backend.api => ApiAlertsRepository(ref.watch(dioProvider)),
  };
});

final registerPushDeviceProvider = Provider<RegisterPushDevice>(
  (ref) => RegisterPushDevice(
    ref.watch(alertsRepositoryProvider),
    ref.watch(pushMessagingProvider),
  ),
);
