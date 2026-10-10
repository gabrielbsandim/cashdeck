import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';

/// Forwarding in memory, with fictional apps, for the demo backend.
final class FakeCardNotificationBridge implements CardNotificationBridge {
  new({this.access = false});

  bool access;
  CardNotificationConfig _config = CardNotificationConfig.off;

  static const apps = [
    NotifyingApp(package: 'com.example.cardapp', label: 'Card App'),
    NotifyingApp(package: 'com.example.chat', label: 'Chat'),
  ];

  @override
  bool get supported => true;

  CardNotificationStatus get _status => CardNotificationStatus(
    access: access,
    enabled: _config.enabled,
    packages: _config.packages,
    accountId: _config.accountId,
    pending: 0,
    apps: apps,
  );

  @override
  Future<Result<CardNotificationStatus>> status() async => Ok(_status);

  @override
  Future<Result<void>> openAccessSettings() async {
    access = true;
    return const Ok(null);
  }

  @override
  Future<Result<CardNotificationStatus>> configure(
    CardNotificationConfig config,
  ) async {
    _config = config;
    return Ok(_status);
  }
}
