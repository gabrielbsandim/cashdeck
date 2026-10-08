import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';

/// Any token of eight characters or more is accepted.
final class FakeServerAccessRepository implements ServerAccessRepository {
  new({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  final List<ServerCredentials> checked = [];

  @override
  Future<Result<void>> check(ServerCredentials credentials) async {
    await Future<void>.delayed(latency);
    checked.add(credentials);
    if (credentials.token.length < 8) return const Err(UnauthorizedFailure());
    return const Ok(null);
  }
}
