import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps the server address and this device's session token. Older versions
/// kept the server's static token instead; [readLegacy] finds it so it can be
/// exchanged once and deleted.
abstract interface class CredentialStore {
  Future<ServerCredentials?> read();

  Future<void> write(ServerCredentials credentials);

  Future<void> clear();

  Future<ServerCredentials?> readLegacy();

  Future<void> clearLegacy();
}

final class InMemoryCredentialStore implements CredentialStore {
  new([this._credentials, this._legacy]);

  ServerCredentials? _credentials;
  ServerCredentials? _legacy;

  @override
  Future<ServerCredentials?> read() async => _credentials;

  @override
  Future<void> write(ServerCredentials credentials) async =>
      _credentials = credentials;

  @override
  Future<void> clear() async {
    _credentials = null;
    _legacy = null;
  }

  @override
  Future<ServerCredentials?> readLegacy() async => _legacy;

  @override
  Future<void> clearLegacy() async => _legacy = null;
}

/// The Keychain on iOS and the Keystore-backed storage on Android.
final class SecureCredentialStore implements CredentialStore {
  const new([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static const urlKey = 'server_url';
  static const tokenKey = 'session_token';

  /// Where versions before device sessions kept the static API token.
  static const legacyTokenKey = 'access_token';

  Future<ServerCredentials?> _readWith(String key) async {
    final url = await _storage.read(key: urlKey);
    final token = await _storage.read(key: key);
    if (url == null || token == null) return null;
    return ServerCredentials(baseUrl: url, token: token);
  }

  @override
  Future<ServerCredentials?> read() => _readWith(tokenKey);

  @override
  Future<void> write(ServerCredentials credentials) async {
    await _storage.write(key: urlKey, value: credentials.baseUrl);
    await _storage.write(key: tokenKey, value: credentials.token);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: urlKey);
    await _storage.delete(key: tokenKey);
    await clearLegacy();
  }

  @override
  Future<ServerCredentials?> readLegacy() => _readWith(legacyTokenKey);

  @override
  Future<void> clearLegacy() => _storage.delete(key: legacyTokenKey);
}
