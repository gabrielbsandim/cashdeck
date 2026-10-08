import 'package:cashdeck/core/result/result.dart';
import 'package:equatable/equatable.dart';

/// The self-hosted server the app talks to, and whether anyone signed up.
final class ServerInfo extends Equatable {
  const new({required this.host, required this.hasUsers});

  final String host;
  final bool hasUsers;

  @override
  List<Object?> get props => [host, hasUsers];
}

final class UserSession extends Equatable {
  const new({required this.name, required this.email});

  final String name;
  final String email;

  /// The first name, as the unlock screen greets.
  String get firstName => name.trim().split(' ').first;

  @override
  List<Object?> get props => [name, email];
}

enum PasswordStrength { weak, fair, strong }

/// Twelve characters with three kinds of character is strong; eight is
/// fair; anything shorter is weak.
PasswordStrength passwordStrengthOf(String password) {
  final kinds = [
    RegExp('[a-z]'),
    RegExp('[A-Z]'),
    RegExp('[0-9]'),
    RegExp('[^a-zA-Z0-9]'),
  ].where((kind) => kind.hasMatch(password)).length;
  if (password.length >= 12 && kinds >= 3) return PasswordStrength.strong;
  if (password.length >= 8) return PasswordStrength.fair;
  return PasswordStrength.weak;
}

enum SignUpField { name, email, password, confirmation }

/// The fields of a first sign-up that cannot be sent as they are.
Set<SignUpField> signUpErrorsOf({
  required String name,
  required String email,
  required String password,
  required String confirmation,
}) => {
  if (name.trim().isEmpty) SignUpField.name,
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim()))
    SignUpField.email,
  if (passwordStrengthOf(password) == PasswordStrength.weak)
    SignUpField.password,
  if (confirmation != password) SignUpField.confirmation,
};

abstract interface class AccountRepository {
  Future<Result<ServerInfo>> server();

  Future<Result<UserSession>> signUp({
    required String name,
    required String email,
    required String password,
  });

  Future<Result<UserSession>> signIn({
    required String email,
    required String password,
  });

  Future<Result<UserSession>> session();

  Future<Result<UserSession>> unlock(String password);
}
