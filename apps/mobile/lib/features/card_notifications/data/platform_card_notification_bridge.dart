import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';
import 'package:flutter/services.dart';

CardNotificationStatus cardNotificationStatusFromMap(
  Map<Object?, Object?> map,
) => CardNotificationStatus(
  access: map['access'] == true,
  enabled: map['enabled'] == true,
  packages: {...(map['packages'] as List<Object?>? ?? []).whereType<String>()},
  accountId: map['accountId'] as String?,
  pending: map['pending'] as int? ?? 0,
  apps: [
    for (final app
        in (map['apps'] as List<Object?>? ?? [])
            .whereType<Map<Object?, Object?>>())
      NotifyingApp(
        package: app['package']! as String,
        label: app['label']! as String,
      ),
  ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
);

/// The Android listener behind a method channel.
final class PlatformCardNotificationBridge implements CardNotificationBridge {
  const new({this.supported = true, this._channel = defaultChannel});

  static const defaultChannel = MethodChannel(
    'io.cashdeck.app/card_notifications',
  );

  final MethodChannel _channel;

  @override
  final bool supported;

  @override
  Future<Result<CardNotificationStatus>> status() =>
      _read(() => _channel.invokeMethod<Object?>('status'));

  @override
  Future<Result<void>> openAccessSettings() async {
    if (!supported) return const Err(UnsupportedFailure());
    try {
      await _channel.invokeMethod<void>('openAccessSettings');
      return const Ok(null);
    } on PlatformException {
      return const Err(UnexpectedFailure());
    }
  }

  @override
  Future<Result<CardNotificationStatus>> configure(
    CardNotificationConfig config,
  ) => _read(
    () => _channel.invokeMethod<Object?>('configure', {
      'enabled': config.enabled,
      'packages': config.packages.toList(),
      'accountId': config.accountId,
      'baseUrl': config.baseUrl,
      'token': config.token,
    }),
  );

  Future<Result<CardNotificationStatus>> _read(
    Future<Object?> Function() call,
  ) async {
    if (!supported) return const Ok(CardNotificationStatus.unsupported);
    try {
      final answer = await call();
      if (answer is! Map<Object?, Object?>) {
        return const Err(UnexpectedFailure());
      }
      return Ok(cardNotificationStatusFromMap(answer));
    } on PlatformException {
      return const Err(UnexpectedFailure());
    } on MissingPluginException {
      return const Ok(CardNotificationStatus.unsupported);
    }
  }
}
