import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';

/// Trades the address and static token for a session of this device and
/// returns what to keep; storing it is the session's job.
final class SignIn {
  const new(this._repository, this._device);

  final ServerAccessRepository _repository;
  final DeviceIdentity _device;

  Future<Result<ServerCredentials>> call({
    required String serverUrl,
    required String token,
  }) async {
    final errors = signInErrorsOf(serverUrl: serverUrl, token: token);
    if (errors.isNotEmpty) {
      return Err(
        ValidationFailure([for (final field in errors) field.name].join(', ')),
      );
    }
    final staticToken = ServerCredentials(
      baseUrl: normalizeServerUrl(serverUrl),
      token: token.trim(),
    );
    return await _repository.exchange(staticToken, _device);
  }
}
