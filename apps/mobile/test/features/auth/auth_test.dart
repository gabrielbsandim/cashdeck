import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/auth/application/account_use_cases.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/data/fake_account_repository.dart';
import 'package:cashdeck/features/auth/domain/account.dart';
import 'package:cashdeck/features/auth/presentation/account_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('password strength grows with length and variety', () {
    expect(passwordStrengthOf('abc'), PasswordStrength.weak);
    expect(passwordStrengthOf('abcdefgh'), PasswordStrength.fair);
    expect(passwordStrengthOf('abcdefghijkl'), PasswordStrength.fair);
    expect(passwordStrengthOf('Abcdefghijk1'), PasswordStrength.strong);
    expect(passwordStrengthOf('abcdefghij1!'), PasswordStrength.strong);
  });

  test('a sign-up form names every field it cannot send', () {
    expect(
      signUpErrorsOf(
        name: ' ',
        email: 'sem-arroba',
        password: 'curta',
        confirmation: 'outra',
      ),
      SignUpField.values.toSet(),
    );
    expect(
      signUpErrorsOf(
        name: 'Pessoa Exemplo',
        email: 'pessoa@exemplo.com',
        password: 'senha-segura',
        confirmation: 'senha-segura',
      ),
      isEmpty,
    );
  });

  test('a session greets by first name and compares by value', () {
    const session = UserSession(name: '  Pessoa Exemplo', email: 'p@e.com');
    const server = ServerInfo(host: 'casa.local', hasUsers: false);

    expect(session.firstName, 'Pessoa');
    expect(session.props, ['  Pessoa Exemplo', 'p@e.com']);
    expect(server.props, ['casa.local', false]);
  });

  group('the fake server', () {
    late FakeAccountRepository repository;
    late SignUp signUp;

    setUp(() {
      repository = FakeAccountRepository(latency: Duration.zero);
      signUp = SignUp(repository);
    });

    test('refuses a bad form before calling the server', () async {
      final result = await signUp(
        name: '',
        email: 'x',
        password: 'a',
        confirmation: 'b',
      );

      expect(
        result,
        const Err<UserSession>(
          ValidationFailure('name, email, password, confirmation'),
        ),
      );
      expect(await repository.server(), isA<Ok<ServerInfo>>());
      expect(
        (await repository.server() as Ok<ServerInfo>).value.hasUsers,
        isFalse,
      );
    });

    test('creates the first user once, then signs in and unlocks', () async {
      expect(
        (await repository.session() as Ok<UserSession>).value.firstName,
        'Marina',
      );
      expect(await repository.unlock('qualquer'), isA<Ok<UserSession>>());
      expect(
        await repository.unlock(''),
        const Err<UserSession>(UnauthorizedFailure()),
      );
      expect(
        await repository.signIn(email: 'a@b.com', password: 'x'),
        const Err<UserSession>(UnauthorizedFailure()),
      );

      final created = await signUp(
        name: ' Pessoa Exemplo ',
        email: 'pessoa@exemplo.com',
        password: 'senha-segura',
        confirmation: 'senha-segura',
      );
      expect(
        created,
        const Ok(
          UserSession(name: 'Pessoa Exemplo', email: 'pessoa@exemplo.com'),
        ),
      );
      expect(
        await repository.signUp(
          name: 'Outra',
          email: 'outra@exemplo.com',
          password: 'senha-segura',
        ),
        const Err<UserSession>(ForbiddenFailure()),
      );
      expect(
        (await repository.server() as Ok<ServerInfo>).value.hasUsers,
        isTrue,
      );
      expect(
        await repository.signIn(
          email: 'pessoa@exemplo.com',
          password: 'senha-segura',
        ),
        isA<Ok<UserSession>>(),
      );
      expect(
        await repository.signIn(
          email: 'pessoa@exemplo.com',
          password: 'errada',
        ),
        const Err<UserSession>(UnauthorizedFailure()),
      );
      expect(
        await repository.unlock('errada'),
        const Err<UserSession>(UnauthorizedFailure()),
      );
      expect(await repository.unlock('senha-segura'), isA<Ok<UserSession>>());
      expect(
        (await repository.session() as Ok<UserSession>).value.firstName,
        'Pessoa',
      );
    });
  });

  test('both backends read the fake account and expose it', () async {
    final container = ProviderContainer(
      overrides: [
        accountRepositoryProvider.overrideWithValue(
          FakeAccountRepository(latency: Duration.zero),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(signUpProvider), isA<SignUp>());
    expect(
      (await container.read(serverInfoProvider.future)).host,
      FakeAccountRepository.host,
    );
    expect((await container.read(sessionProvider.future)).firstName, 'Marina');
  });

  test('the default provider is the fake', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(accountRepositoryProvider),
      isA<FakeAccountRepository>(),
    );
  });
}
