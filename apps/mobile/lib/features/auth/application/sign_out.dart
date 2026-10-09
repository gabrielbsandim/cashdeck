import 'package:cashdeck/features/alerts/application/register_push_device.dart';

/// Forgets the push token while the credentials still authenticate the
/// request, then clears the session; a failed removal never blocks leaving.
final class SignOut {
  const new(this._unregister, this._clearSession);

  final UnregisterPushDevice _unregister;
  final Future<void> Function() _clearSession;

  Future<void> call() async {
    await _unregister();
    await _clearSession();
  }
}
