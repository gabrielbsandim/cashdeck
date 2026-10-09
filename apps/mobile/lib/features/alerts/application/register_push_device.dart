import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';

/// Hands this device's push token to the server, when push is available.
/// Answers whether a token was registered.
final class RegisterPushDevice {
  const new(this._repository, this._push);

  final AlertsRepository _repository;
  final PushMessaging _push;

  Future<bool> call({required String platform, String? token}) async {
    final current = token ?? await _push.token();
    if (current == null) return false;
    final result = await _repository.registerDevice(current, platform);
    return result is Ok;
  }
}

/// Drops this device's push token from the server, so a signed-out phone
/// stops receiving alerts. Answers whether the server forgot it.
final class UnregisterPushDevice {
  const new(this._repository, this._push);

  final AlertsRepository _repository;
  final PushMessaging _push;

  Future<bool> call() async {
    final token = await _push.token();
    if (token == null) return false;
    return await _repository.removeDevice(token) is Ok;
  }
}
