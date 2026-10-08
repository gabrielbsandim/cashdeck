import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';

enum SignInField { serverUrl, token }

/// The fields of the sign-in form that cannot be sent as they are.
Set<SignInField> signInErrorsOf({
  required String serverUrl,
  required String token,
}) => {
  if (!isValidServerUrl(serverUrl)) SignInField.serverUrl,
  if (token.trim().isEmpty) SignInField.token,
};

/// Asks the server whether it accepts a token.
abstract interface class ServerAccessRepository {
  Future<Result<void>> check(ServerCredentials credentials);
}
