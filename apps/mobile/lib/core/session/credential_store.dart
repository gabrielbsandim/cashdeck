import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialStore {
  Future<ServerCredentials?> read();

  Future<void> write(ServerCredentials credentials);

  Future<void> clear();
}

final class InMemoryCredentialStore implements CredentialStore {
  new([this._credentials]);

  ServerCredentials? _credentials;

  @override
  Future<ServerCredentials?> read() async => _credentials;

  @override
  Future<void> write(ServerCredentials credentials) async =>
      _credentials = credentials;

  @override
  Future<void> clear() async => _credentials = null;
}

/// The Keychain on iOS and the Keystore-backed storage on Android.
final class SecureCredentialStore implements CredentialStore {
  const new([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const urlKey = 'server_url';
  static const tokenKey = 'access_token';

  @override
  Future<ServerCredentials?> read() async {
    final url = await _storage.read(key: urlKey);
    final token = await _storage.read(key: tokenKey);
    if (url == null || token == null) return null;
    return ServerCredentials(baseUrl: url, token: token);
  }

  @override
  Future<void> write(ServerCredentials credentials) async {
    await _storage.write(key: urlKey, value: credentials.baseUrl);
    await _storage.write(key: tokenKey, value: credentials.token);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: urlKey);
    await _storage.delete(key: tokenKey);
  }
}
