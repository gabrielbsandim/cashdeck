import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/location/location_reader.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/features/settings/presentation/safe_zone_screen.dart';
import 'package:cashdeck/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/pump_app.dart';
import '../../../support/safe_mode_support.dart';

void main() {
  String released() => l10n.safeZoneReleased(
    DateFormat.Hm('pt-BR')
        .format(testNow.add(SafeModeController.releaseWindow).toLocal()),
  );

  Future<void> tapVersion(WidgetTester tester, int times) async {
    for (var tap = 0; tap < times; tap++) {
      await tester.tap(find.byKey(SettingsScreen.versionKey));
      await tester.pump();
    }
    await settle(tester);
  }

  testWidgets('saves this place and removes it again', (tester) async {
    final reader = FakeLocationReader(homePoint);
    final app = await pumpRoute(
      tester,
      AppRoutes.safeZone,
      overrides: [locationReaderProvider.overrideWithValue(reader)],
    );
    expect(find.text(l10n.safeZoneOff), findsOneWidget);
    expect(find.text(l10n.safeZoneEmpty), findsOneWidget);

    await tester.tap(find.byKey(SafeZoneScreen.addKey));
    await settle(tester);
    expect(find.text(l10n.safeZoneSaved), findsOneWidget);
    expect(find.text(l10n.safeZoneItem(1, 300)), findsOneWidget);
    expect(find.text(l10n.safeZoneInside), findsOneWidget);
    await waitForToast(tester);

    await tester.tap(find.byKey(SafeZoneScreen.removeKey(0)));
    await settle(tester);
    expect(app.read(safeModeProvider).enabled, isFalse);

    reader.point = null;
    await tester.tap(find.byKey(SafeZoneScreen.addKey));
    await settle(tester);
    expect(find.text(l10n.safeZoneNoLocation), findsOneWidget);
  });

  testWidgets('away from home the zones lock and the note says why', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.safeZone, overrides: safeModeOverrides());

    expect(find.text(l10n.safeZoneOutside), findsOneWidget);
    expect(find.byKey(SafeZoneScreen.limitedNoteKey), findsOneWidget);
    final add = tester.widget<CdButton>(find.byKey(SafeZoneScreen.addKey));
    expect(add.onPressed, isNull);
    final remove = tester.widget<IconButton>(
      find.byKey(SafeZoneScreen.removeKey(0)),
    );
    expect(remove.onPressed, isNull);
  });

  testWidgets('ten quick taps on the version release the app for an hour', (
    tester,
  ) async {
    final biometrics = FakeBiometricAuthenticator();
    final app = await pumpRoute(
      tester,
      AppRoutes.settings,
      overrides: [
        ...safeModeOverrides(),
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
      ],
    );
    expect(find.byKey(SettingsScreen.pauseKey), findsNothing);
    expect(
      find.byKey(SettingsScreen.rowKey(AppRoutes.entityProfiles)),
      findsNothing,
    );
    final hide = tester.widget<Switch>(
      find.descendant(
        of: find.byKey(SettingsScreen.hideAmountsKey),
        matching: find.byType(Switch),
      ),
    );
    expect(hide.value, isTrue);
    expect(hide.onChanged, isNull);

    await tapVersion(tester, 9);
    expect(biometrics.reasons, isEmpty);
    await tapVersion(tester, 1);
    expect(biometrics.reasons, [l10n.safeZoneReleaseReason]);
    expect(app.read(safeModeLimitedProvider), isFalse);
    expect(find.text(released()), findsWidgets);
    expect(find.byKey(SettingsScreen.pauseKey), findsOneWidget);
    await waitForToast(tester);

    await tester.tap(find.byKey(SettingsScreen.rowKey(AppRoutes.safeZone)));
    await settle(tester);
    await tester.tap(find.byKey(SafeZoneScreen.endReleaseKey));
    await settle(tester);
    expect(app.read(safeModeLimitedProvider), isTrue);
  });

  testWidgets('slow taps, a failed check or no limit release nothing', (
    tester,
  ) async {
    final biometrics = FakeBiometricAuthenticator(approve: false);
    final app = await pumpRoute(
      tester,
      AppRoutes.settings,
      overrides: [
        ...safeModeOverrides(),
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
      ],
    );
    await tapVersion(tester, 10);
    expect(biometrics.reasons, hasLength(1));
    expect(app.read(safeModeLimitedProvider), isTrue);

    final clock = app.read(clockProvider) as FixedClock;
    for (var tap = 0; tap < 10; tap++) {
      clock.current = clock.current.add(const Duration(seconds: 3));
      await tapVersion(tester, 1);
    }
    expect(biometrics.reasons, hasLength(1));
  });

  testWidgets('at home the taps do nothing', (tester) async {
    final biometrics = FakeBiometricAuthenticator();
    await pumpRoute(
      tester,
      AppRoutes.settings,
      overrides: [
        ...safeModeOverrides(at: homePoint),
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
      ],
    );
    expect(find.text(l10n.safeZoneInside), findsOneWidget);

    await tapVersion(tester, 10);

    expect(biometrics.reasons, isEmpty);
  });

  testWidgets('away from home a closed screen sends back home', (tester) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.chat,
      overrides: safeModeOverrides(),
    );

    expect(app.location, AppRoutes.home);
  });
}
