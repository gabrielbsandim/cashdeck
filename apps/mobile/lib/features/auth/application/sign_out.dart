import 'package:cashdeck/features/alerts/application/register_push_device.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';

/// Forgets the push token and ends the server session while the credentials
/// still authenticate the requests, then clears the local session; a failed
/// call never blocks leaving. [_stopForwarding] keeps a signed-out phone from
/// sending with the old token.
final class SignOut {
  const new(
    this._unregister,
    this._clearSession, [
    this._stopForwarding,
    this._sessions,
  ]);

  final UnregisterPushDevice _unregister;
  final Future<void> Function() _clearSession;
  final Future<void> Function()? _stopForwarding;
  final DeviceSessionsRepository? _sessions;

  Future<void> call() async {
    await _unregister();
    await _stopForwarding?.call();
    await _sessions?.endCurrent();
    await _clearSession();
  }
}
