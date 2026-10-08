import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';

/// Checks the address and token against the server and returns what to
/// keep; storing them is the session's job.
final class SignIn {
  const new(this._repository);

  final ServerAccessRepository _repository;

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
    final credentials = ServerCredentials(
      baseUrl: normalizeServerUrl(serverUrl),
      token: token.trim(),
    );
    return switch (await _repository.check(credentials)) {
      Ok() => Ok(credentials),
      Err(:final failure) => Err(failure),
    };
  }
}
