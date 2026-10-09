import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/security/app_lock.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/features/auth/presentation/server_sign_in_screen.dart';
import 'package:cashdeck/features/auth/presentation/unlock_screen.dart';
import 'package:cashdeck/features/settings/presentation/more_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';

void main() {
  Future<void> type(WidgetTester tester, Key key, String text) async {
    await tester.enterText(
      find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
      text,
    );
    await tester.pump();
  }

  testWidgets('signed out, the app opens on sign-in and connects', (
    tester,
  ) async {
    final store = InMemoryCredentialStore();
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        initialCredentialsProvider.overrideWithValue(null),
        credentialStoreProvider.overrideWithValue(store),
      ],
    );
    expect(app.location, AppRoutes.signIn);
    expect(find.text(l10n.signInTitle), findsOneWidget);

    await type(tester, ServerSignInScreen.urlKey, 'ftp://');
    await tester.tap(find.byKey(ServerSignInScreen.submitKey));
    await settle(tester);
    expect(find.text(l10n.errorServerUrlInvalid), findsOneWidget);
    expect(find.text(l10n.errorTokenRequired), findsOneWidget);

    await type(tester, ServerSignInScreen.urlKey, 'cashdeck.casa');
    await type(tester, ServerSignInScreen.tokenKey, 'curto');
    await tester.tap(find.byKey(ServerSignInScreen.submitKey));
    await settle(tester);
    expect(find.text(l10n.errorSessionExpired), findsOneWidget);
    expect(app.location, AppRoutes.signIn);

    await type(tester, ServerSignInScreen.tokenKey, 'token-de-teste');
    await tester.tap(find.byKey(ServerSignInScreen.submitKey));
    await settle(tester);
    expect(app.location, AppRoutes.home);
    expect(
      await store.read(),
      const ServerCredentials(
        baseUrl: 'https://cashdeck.casa',
        token: 'token-de-teste',
      ),
    );
    await waitForToast(tester);
  });

  testWidgets('a locked app unlocks with the device check', (tester) async {
    final biometrics = FakeBiometricAuthenticator(approve: false);
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        initiallyLockedProvider.overrideWithValue(true),
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
      ],
    );
    expect(app.location, AppRoutes.unlock);
    expect(find.text(ServerCredentials.demo.host), findsOneWidget);
    expect(biometrics.reasons, hasLength(1));
    expect(find.text(l10n.confirmDenied), findsOneWidget);

    biometrics.approve = true;
    await tester.tap(find.byKey(UnlockScreen.sensorKey));
    await settle(tester);
    expect(app.location, AppRoutes.home);
    expect(biometrics.reasons, hasLength(2));
  });

  testWidgets('signs out from the lock screen', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        initiallyLockedProvider.overrideWithValue(true),
        biometricAuthenticatorProvider.overrideWithValue(
          FakeBiometricAuthenticator(approve: false),
        ),
      ],
    );

    await tester.tap(find.byKey(UnlockScreen.signOutKey));
    await settle(tester);

    expect(app.location, AppRoutes.signIn);
    expect(app.read(serverSessionProvider), isNull);
  });

  testWidgets('More locks the app and signs out', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.more,
      overrides: [
        biometricAuthenticatorProvider.overrideWithValue(
          FakeBiometricAuthenticator(approve: false),
        ),
      ],
    );

    await tester.tap(find.byKey(MoreScreen.rowKey(AppRoutes.unlock)));
    await settle(tester);
    expect(app.location, AppRoutes.unlock);

    app.read(appLockProvider.notifier).unlock();
    await settle(tester);
    expect(app.location, AppRoutes.home);

    app.router.go(AppRoutes.more);
    await settle(tester);
    await tester.tap(find.byKey(MoreScreen.signOutKey));
    await settle(tester);
    expect(app.location, AppRoutes.signIn);
  });
}
