import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';

/// This phone plus a fictional tablet, until one is revoked.
final class FakeDeviceSessionsRepository implements DeviceSessionsRepository {
  new({required DateTime now, this.latency = const Duration(milliseconds: 300)})
    : _sessions = [
        DeviceSession(
          id: 'session-phone',
          deviceName: 'Android',
          platform: SessionPlatform.android,
          createdAt: now.subtract(const Duration(days: 12)),
          lastUsedAt: now,
          current: true,
        ),
        DeviceSession(
          id: 'session-tablet',
          deviceName: 'iPad',
          platform: SessionPlatform.ios,
          createdAt: now.subtract(const Duration(days: 40)),
          lastUsedAt: now.subtract(const Duration(days: 3)),
          current: false,
        ),
      ];

  final Duration latency;
  final List<DeviceSession> _sessions;
  bool ended = false;

  @override
  Future<Result<List<DeviceSession>>> list() async {
    await Future<void>.delayed(latency);
    return Ok(List.unmodifiable(_sessions));
  }

  @override
  Future<Result<void>> revoke(String id) async {
    await Future<void>.delayed(latency);
    final before = _sessions.length;
    _sessions.removeWhere((session) => session.id == id);
    if (_sessions.length == before) return const Err(NotFoundFailure());
    return const Ok(null);
  }

  @override
  Future<Result<void>> endCurrent() async {
    await Future<void>.delayed(latency);
    ended = true;
    _sessions.removeWhere((session) => session.current);
    return const Ok(null);
  }
}
