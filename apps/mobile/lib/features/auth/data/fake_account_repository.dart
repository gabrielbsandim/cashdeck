import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/auth/domain/account.dart';

/// A fresh server with no users until the first sign-up, then that user.
final class FakeAccountRepository implements AccountRepository {
  new({this.latency = const Duration(milliseconds: 300)});

  final Duration latency;
  static const host = 'cashdeck.casa.local';
  static const _demo = UserSession(
    name: 'Marina Souza',
    email: 'marina.souza@exemplo.com',
  );

  UserSession? _user;
  String? _password;

  Future<void> _wait() => Future<void>.delayed(latency);

  @override
  Future<Result<ServerInfo>> server() async {
    await _wait();
    return Ok(ServerInfo(host: host, hasUsers: _user != null));
  }

  @override
  Future<Result<UserSession>> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await _wait();
    if (_user != null) return const Err(ForbiddenFailure());
    final user = UserSession(name: name.trim(), email: email.trim());
    _user = user;
    _password = password;
    return Ok(user);
  }

  @override
  Future<Result<UserSession>> signIn({
    required String email,
    required String password,
  }) async {
    await _wait();
    final user = _user;
    if (user == null || user.email != email.trim() || password != _password) {
      return const Err(UnauthorizedFailure());
    }
    return Ok(user);
  }

  @override
  Future<Result<UserSession>> session() async {
    await _wait();
    return Ok(_user ?? _demo);
  }

  @override
  Future<Result<UserSession>> unlock(String password) async {
    await _wait();
    final expected = _password;
    if (expected != null && password != expected) {
      return const Err(UnauthorizedFailure());
    }
    if (password.isEmpty) return const Err(UnauthorizedFailure());
    return Ok(_user ?? _demo);
  }
}
