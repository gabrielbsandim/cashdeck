import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:equatable/equatable.dart';

/// A device signed in to the server; [current] is this phone.
final class DeviceSession extends Equatable {
  const new({
    required this.id,
    required this.deviceName,
    required this.platform,
    required this.createdAt,
    required this.lastUsedAt,
    required this.current,
  });

  final String id;
  final String deviceName;
  final SessionPlatform platform;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final bool current;

  @override
  List<Object?> get props => [
    id,
    deviceName,
    platform,
    createdAt,
    lastUsedAt,
    current,
  ];
}

/// This phone first, then the most recently used.
List<DeviceSession> orderDeviceSessions(Iterable<DeviceSession> sessions) =>
    [...sessions]..sort((a, b) {
      if (a.current != b.current) return a.current ? -1 : 1;
      return b.lastUsedAt.compareTo(a.lastUsedAt);
    });

abstract interface class DeviceSessionsRepository {
  Future<Result<List<DeviceSession>>> list();

  Future<Result<void>> revoke(String id);

  /// Ends the session this phone signs its requests with.
  Future<Result<void>> endCurrent();
}
