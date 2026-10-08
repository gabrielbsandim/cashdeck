import 'package:cashdeck/features/auth/application/account_use_cases.dart';
import 'package:cashdeck/features/auth/data/fake_account_repository.dart';
import 'package:cashdeck/features/auth/domain/account.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// No account endpoint yet, so both backends read the fake.
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => FakeAccountRepository(),
);

final signUpProvider = Provider<SignUp>(
  (ref) => SignUp(ref.watch(accountRepositoryProvider)),
);
