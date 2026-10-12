import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';

/// What the phone is signed in with at launch. A static token left by an
/// older version is exchanged for a session once and then deleted; a refused
/// one is deleted too, while a network failure keeps it for the next launch.
final class RestoreSession {
  const new(this._store, this._repository, this._device);

  final CredentialStore _store;
  final ServerAccessRepository _repository;
  final DeviceIdentity _device;

  Future<ServerCredentials?> call() async {
    final session = await _store.read();
    if (session != null) {
      await _store.clearLegacy();
      return session;
    }
    final legacy = await _store.readLegacy();
    if (legacy == null) return null;
    switch (await _repository.exchange(legacy, _device)) {
      case Ok(:final value):
        await _store.write(value);
        await _store.clearLegacy();
        return value;
      case Err(failure: UnauthorizedFailure()):
        await _store.clearLegacy();
        return null;
      case Err():
        return null;
    }
  }
}
