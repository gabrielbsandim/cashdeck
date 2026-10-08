import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/data/fake_account_repository.dart';
import 'package:cashdeck/features/auth/domain/account.dart';
import 'package:cashdeck/features/auth/presentation/unlock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';

final class _BrokenServer implements AccountRepository {
  final _inner = FakeAccountRepository(latency: Duration.zero);
  bool broken = true;

  @override
  Future<Result<ServerInfo>> server() async {
    if (broken) return const Err(NetworkFailure());
    return await _inner.server();
  }

  @override
  Future<Result<UserSession>> signUp({
    required String name,
    required String email,
    required String password,
  }) => _inner.signUp(name: name, email: email, password: password);

  @override
  Future<Result<UserSession>> signIn({
    required String email,
    required String password,
  }) => _inner.signIn(email: email, password: password);

  @override
  Future<Result<UserSession>> session() => _inner.session();

  @override
  Future<Result<UserSession>> unlock(String password) =>
      _inner.unlock(password);
}

void main() {
  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pump();
  }

  testWidgets('creates the first user after the form is valid', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.signUp);
    expect(find.text(l10n.signUpTitle), findsOneWidget);
    expect(find.text(FakeAccountRepository.host), findsOneWidget);

    await tester.tap(find.byKey(const Key('sign-up-submit')));
    await settle(tester);
    expect(find.text(l10n.errorNameRequired), findsOneWidget);
    expect(find.text(l10n.errorEmailInvalid), findsOneWidget);
    expect(find.text(l10n.errorPasswordWeak), findsOneWidget);

    await type(tester, 'sign-up-name', 'Pessoa Exemplo');
    await type(tester, 'sign-up-email', 'pessoa@exemplo.com');
    await type(tester, 'sign-up-password', 'curta');
    expect(
      find.text(l10n.passwordStrengthLine(l10n.passwordWeak, 5)),
      findsOneWidget,
    );
    await type(tester, 'sign-up-password', 'senhasegura');
    expect(
      find.text(l10n.passwordStrengthLine(l10n.passwordFair, 11)),
      findsOneWidget,
    );
    await type(tester, 'sign-up-password', 'Senha-Segura-1');
    expect(
      find.text(l10n.passwordStrengthLine(l10n.passwordStrong, 14)),
      findsOneWidget,
    );
    await type(tester, 'sign-up-confirmation', 'outra');
    await tester.tap(find.byKey(const Key('sign-up-submit')));
    await settle(tester);
    expect(find.text(l10n.errorPasswordMismatch), findsOneWidget);

    await type(tester, 'sign-up-confirmation', 'Senha-Segura-1');
    await tester.tap(find.byKey(const Key('sign-up-submit')));
    await settle(tester);

    expect(app.location, AppRoutes.home);
  });

  testWidgets('a server with users signs in instead', (tester) async {
    final repository = FakeAccountRepository(latency: Duration.zero);
    await tester.runAsync(
      () => repository.signUp(
        name: 'Pessoa Exemplo',
        email: 'pessoa@exemplo.com',
        password: 'Senha-Segura-1',
      ),
    );
    final app = await pumpRoute(
      tester,
      AppRoutes.signUp,
      overrides: [accountRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.text(l10n.signInTitle), findsWidgets);
    expect(find.byKey(const Key('sign-up-name')), findsNothing);

    await type(tester, 'sign-up-email', 'pessoa@exemplo.com');
    await type(tester, 'sign-up-password', 'Senha-Errada-1');
    await tester.tap(find.byKey(const Key('sign-up-submit')));
    await settle(tester);
    expect(find.text(l10n.errorSessionExpired), findsOneWidget);

    await type(tester, 'sign-up-password', 'Senha-Segura-1');
    await tester.tap(find.byKey(const Key('sign-up-submit')));
    await settle(tester);
    expect(app.location, AppRoutes.home);
  });

  testWidgets('an unreachable server offers a retry', (tester) async {
    final repository = _BrokenServer();
    await pumpRoute(
      tester,
      AppRoutes.signUp,
      overrides: [accountRepositoryProvider.overrideWithValue(repository)],
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository.broken = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    expect(find.text(l10n.signUpTitle), findsOneWidget);
  });

  testWidgets('unlocks with the device check', (tester) async {
    final biometrics = FakeBiometricAuthenticator(approve: false);
    final app = await pumpRoute(
      tester,
      AppRoutes.unlock,
      overrides: [biometricAuthenticatorProvider.overrideWithValue(biometrics)],
    );
    expect(find.text(l10n.unlockTitle('Marina')), findsOneWidget);
    expect(find.text(FakeAccountRepository.host), findsOneWidget);

    await tester.tap(find.byKey(UnlockScreen.sensorKey));
    await settle(tester);
    expect(find.text(l10n.confirmDenied), findsOneWidget);

    biometrics.approve = true;
    await tester.tap(find.byKey(UnlockScreen.sensorKey));
    await settle(tester);
    expect(app.location, AppRoutes.home);
    expect(biometrics.reasons, hasLength(2));
  });

  testWidgets('unlocks with the password', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.unlock);

    await tester.tap(find.byKey(UnlockScreen.passwordToggleKey));
    await settle(tester);
    await tester.tap(find.byKey(UnlockScreen.submitKey));
    await settle(tester);
    expect(find.text(l10n.errorSessionExpired), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(UnlockScreen.passwordKey),
        matching: find.byType(TextField),
      ),
      'qualquer',
    );
    await tester.tap(find.byKey(UnlockScreen.submitKey));
    await settle(tester);
    expect(app.location, AppRoutes.home);
  });

  testWidgets('switches back to the sensor', (tester) async {
    await pumpRoute(tester, AppRoutes.unlock);

    await tester.tap(find.byKey(UnlockScreen.passwordToggleKey));
    await settle(tester);
    expect(find.byKey(UnlockScreen.sensorKey), findsNothing);
    await tester.tap(find.byKey(UnlockScreen.passwordToggleKey));
    await settle(tester);
    expect(find.byKey(UnlockScreen.sensorKey), findsOneWidget);
  });
}
