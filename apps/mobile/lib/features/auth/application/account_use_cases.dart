import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/auth/domain/account.dart';

/// Creates the first user, refusing a form that has errors.
final class SignUp {
  const new(this._repository);

  final AccountRepository _repository;

  Future<Result<UserSession>> call({
    required String name,
    required String email,
    required String password,
    required String confirmation,
  }) async {
    final errors = signUpErrorsOf(
      name: name,
      email: email,
      password: password,
      confirmation: confirmation,
    );
    if (errors.isNotEmpty) {
      return Err(
        ValidationFailure([for (final field in errors) field.name].join(', ')),
      );
    }
    return await _repository.signUp(
      name: name,
      email: email,
      password: password,
    );
  }
}
