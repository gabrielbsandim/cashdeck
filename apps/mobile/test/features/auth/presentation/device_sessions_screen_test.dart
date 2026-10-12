import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/auth/auth_providers.dart';
import 'package:cashdeck/features/auth/data/fake_device_sessions_repository.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:cashdeck/features/auth/presentation/device_sessions_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/pump_app.dart';

/// Lists fine, but the server refuses to revoke anything.
final class _StubbornSessions implements DeviceSessionsRepository {
  new(this._sessions);

  final DeviceSessionsRepository _sessions;
  bool failList = false;

  @override
  Future<Result<List<DeviceSession>>> list() async =>
      failList ? const Err(NetworkFailure()) : await _sessions.list();

  @override
  Future<Result<void>> revoke(String id) async => const Err(NotFoundFailure());

  @override
  Future<Result<void>> endCurrent() => _sessions.endCurrent();
}

void main() {
  FakeDeviceSessionsRepository fake() =>
      FakeDeviceSessionsRepository(now: testNow, latency: Duration.zero);

  testWidgets('lists this phone first and disconnects another device', (
    tester,
  ) async {
    final biometrics = FakeBiometricAuthenticator();
    final sessions = fake();
    await pumpRoute(
      tester,
      AppRoutes.deviceSessions,
      overrides: [
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
        deviceSessionsRepositoryProvider.overrideWithValue(sessions),
      ],
    );

    expect(find.text(l10n.deviceSessionsTitle), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(DeviceSessionsScreen.rowKey('session-phone')))
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(DeviceSessionsScreen.rowKey('session-tablet')),
            )
            .dy,
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(DeviceSessionsScreen.rowKey('session-phone')),
        matching: find.byKey(DeviceSessionsScreen.currentKey),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(DeviceSessionsScreen.rowKey('session-tablet')));
    await settle(tester);
    expect(find.text(l10n.deviceSessionsRevokeTitle('iPad')), findsOneWidget);
    await tester.tap(find.byKey(CdConfirmSheet.confirmKey));
    await settle(tester);

    expect(biometrics.reasons, hasLength(1));
    expect(
      find.byKey(DeviceSessionsScreen.rowKey('session-tablet')),
      findsNothing,
    );
    expect(find.text(l10n.deviceSessionsRevoked), findsOneWidget);
    expect(sessions.ended, isFalse);
    await waitForToast(tester);
  });

  testWidgets('disconnecting this phone signs out', (tester) async {
    final sessions = fake();
    final app = await pumpRoute(
      tester,
      AppRoutes.deviceSessions,
      overrides: [
        biometricAuthenticatorProvider.overrideWithValue(
          FakeBiometricAuthenticator(),
        ),
        deviceSessionsRepositoryProvider.overrideWithValue(sessions),
      ],
    );

    await tester.tap(find.byKey(DeviceSessionsScreen.rowKey('session-phone')));
    await settle(tester);
    expect(find.text(l10n.deviceSessionsRevokeCurrent), findsOneWidget);
    await tester.tap(find.byKey(CdConfirmSheet.confirmKey));
    await settle(tester);

    expect(sessions.ended, isTrue);
    expect(app.location, AppRoutes.signIn);
    expect(app.read(serverSessionProvider), isNull);
  });

  testWidgets('says when the server refuses, and when the list fails', (
    tester,
  ) async {
    final sessions = _StubbornSessions(fake());
    await pumpRoute(
      tester,
      AppRoutes.deviceSessions,
      overrides: [
        biometricAuthenticatorProvider.overrideWithValue(
          FakeBiometricAuthenticator(),
        ),
        deviceSessionsRepositoryProvider.overrideWithValue(sessions),
      ],
    );

    await tester.tap(find.byKey(DeviceSessionsScreen.rowKey('session-tablet')));
    await settle(tester);
    await tester.tap(find.byKey(CdConfirmSheet.confirmKey));
    await settle(tester);
    expect(
      find.byKey(DeviceSessionsScreen.rowKey('session-tablet')),
      findsOneWidget,
    );
    expect(find.byIcon(Symbols.error_rounded), findsOneWidget);
    await waitForToast(tester);
  });

  testWidgets('a list that fails offers to try again', (tester) async {
    final sessions = _StubbornSessions(fake())..failList = true;
    await pumpRoute(
      tester,
      AppRoutes.deviceSessions,
      overrides: [deviceSessionsRepositoryProvider.overrideWithValue(sessions)],
    );
    expect(find.byType(CdErrorState), findsOneWidget);

    sessions.failList = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);

    expect(
      find.byKey(DeviceSessionsScreen.rowKey('session-tablet')),
      findsOneWidget,
    );
  });

  test('a platform has its own icon', () {
    expect({
      for (final p in SessionPlatform.values) sessionPlatformIcon(p),
    }, hasLength(SessionPlatform.values.length));
  });
}
