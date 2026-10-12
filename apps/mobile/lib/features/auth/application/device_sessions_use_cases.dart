import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';

final class ListDeviceSessions {
  const new(this._repository);

  final DeviceSessionsRepository _repository;

  Future<Result<List<DeviceSession>>> call() async =>
      switch (await _repository.list()) {
        Ok(:final value) => Ok(orderDeviceSessions(value)),
        Err(:final failure) => Err(failure),
      };
}

/// Signs another device out; this phone leaves through SignOut instead.
final class RevokeDeviceSession {
  const new(this._repository);

  final DeviceSessionsRepository _repository;

  Future<Result<void>> call(String id) => _repository.revoke(id);
}
