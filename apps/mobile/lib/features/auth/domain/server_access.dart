import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:equatable/equatable.dart';

enum SignInField { serverUrl, token }

/// The fields of the sign-in form that cannot be sent as they are.
Set<SignInField> signInErrorsOf({
  required String serverUrl,
  required String token,
}) => {
  if (!isValidServerUrl(serverUrl)) SignInField.serverUrl,
  if (token.trim().isEmpty) SignInField.token,
};

/// What the server accepts as a session platform.
enum SessionPlatform { android, ios, web }

/// How this phone names itself in the list of connected devices.
final class DeviceIdentity extends Equatable {
  const new({required this.name, required this.platform});

  final String name;
  final SessionPlatform platform;

  @override
  List<Object?> get props => [name, platform];
}

/// Trades the server's static token for a session token of this device; the
/// static token is never kept.
abstract interface class ServerAccessRepository {
  Future<Result<ServerCredentials>> exchange(
    ServerCredentials staticToken,
    DeviceIdentity device,
  );
}
