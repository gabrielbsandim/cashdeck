import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';

/// Any token of eight characters or more is accepted and traded for a
/// session token derived from it.
final class FakeServerAccessRepository implements ServerAccessRepository {
  new({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  final List<(ServerCredentials, DeviceIdentity)> exchanged = [];

  @override
  Future<Result<ServerCredentials>> exchange(
    ServerCredentials staticToken,
    DeviceIdentity device,
  ) async {
    await Future<void>.delayed(latency);
    exchanged.add((staticToken, device));
    if (staticToken.token.length < 8) return const Err(UnauthorizedFailure());
    return Ok(
      ServerCredentials(
        baseUrl: staticToken.baseUrl,
        token: 'session-${staticToken.token}',
      ),
    );
  }
}
