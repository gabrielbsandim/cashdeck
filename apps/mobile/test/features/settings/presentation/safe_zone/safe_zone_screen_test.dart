import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/location/geocoder.dart';
import 'package:cashdeck/core/location/location_reader.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/features/settings/presentation/safe_zone/safe_zone_screen.dart';
import 'package:cashdeck/features/settings/presentation/safe_zone/safe_zone_sheets.dart';
import 'package:cashdeck/features/settings/presentation/sections/security_settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../../../../support/app_harness.dart';
import '../../../../support/builders.dart';
import '../../../../support/pump_app.dart';
import '../../../../support/safe_mode_support.dart';

void main() {
  String released() => l10n.safeZoneReleased(
    DateFormat.Hm('pt-BR')
        .format(testNow.add(SafeModeController.releaseWindow).toLocal()),
  );

  Future<void> addHere(WidgetTester tester) async {
    await tester.tap(find.byKey(SafeZoneScreen.addKey));
    await settle(tester);
    await tester.tap(find.byKey(SafeZoneAddSheet.hereKey));
    await settle(tester);
  }

  Future<void> tapVersion(WidgetTester tester, int times) async {
    for (var tap = 0; tap < times; tap++) {
      await tester.tap(find.byKey(SettingsScreen.versionKey));
      await tester.pump();
    }
    await settle(tester);
  }

  testWidgets('saves this place by its address, renames and removes it', (
    tester,
  ) async {
    const address = 'Rua das Flores, 10, Centro';
    final reader = FakeLocationReader(homePoint);
    final app = await pumpRoute(
      tester,
      AppRoutes.safeZone,
      overrides: [
        locationReaderProvider.overrideWithValue(reader),
        geocoderProvider.overrideWithValue(FakeGeocoder(address)),
      ],
    );
    expect(find.text(l10n.safeZoneOff), findsOneWidget);
    expect(find.text(l10n.safeZoneEmpty), findsOneWidget);

    await addHere(tester);
    expect(find.text(l10n.safeZoneSaved), findsOneWidget);
    expect(find.text(address), findsOneWidget);
    expect(find.text(l10n.safeZoneRadius(300)), findsOneWidget);
    expect(find.text(l10n.safeZoneInside), findsOneWidget);
    await waitForToast(tester);

    await tester.tap(find.byKey(SafeZoneScreen.renameKey(0)));
    await settle(tester);
    final save = find.byKey(SafeZoneNameSheet.saveKey);
    expect(tester.widget<CdButton>(save).onPressed, isNull);
    await tester.enterText(find.byKey(SafeZoneNameSheet.fieldKey), '  Casa ');
    await tester.pump();
    await tester.tap(save);
    await settle(tester);
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text(l10n.safeZoneRenamed), findsOneWidget);
    expect(app.read(safeModeProvider).zones.single.name, 'Casa');
    await waitForToast(tester);

    await tester.tap(find.byKey(SafeZoneScreen.removeKey(0)));
    await settle(tester);
    expect(app.read(safeModeProvider).enabled, isFalse);

    reader.point = null;
    await addHere(tester);
    expect(find.text(l10n.safeZoneNoLocation), findsOneWidget);
  });

  testWidgets('saves a typed address and says when it is not found', (
    tester,
  ) async {
    final geocoder = FakeGeocoder(null, homePoint);
    final app = await pumpRoute(
      tester,
      AppRoutes.safeZone,
      overrides: [
        locationReaderProvider.overrideWithValue(FakeLocationReader(homePoint)),
        geocoderProvider.overrideWithValue(geocoder),
      ],
    );
    expect(find.text(l10n.safeZoneAdd), findsOneWidget);

    await tester.tap(find.byKey(SafeZoneScreen.addKey));
    await settle(tester);
    final save = find.byKey(SafeZoneAddSheet.saveKey);
    expect(tester.widget<CdButton>(save).onPressed, isNull);
    await tester.enterText(
      find.byKey(SafeZoneAddSheet.addressKey),
      ' Rua A, 1, Cidade ',
    );
    await tester.pump();
    await tester.tap(save);
    await settle(tester);
    expect(geocoder.searched, ['Rua A, 1, Cidade']);
    expect(find.text('Rua A, 1, Cidade'), findsOneWidget);
    expect(find.text(l10n.safeZoneInside), findsOneWidget);
    expect(app.read(safeModeLimitedProvider), isFalse);
    await waitForToast(tester);

    geocoder.point = null;
    await tester.tap(find.byKey(SafeZoneScreen.addKey));
    await settle(tester);
    await tester.enterText(find.byKey(SafeZoneAddSheet.addressKey), 'Nada');
    await tester.pump();
    await tester.tap(find.byKey(SafeZoneAddSheet.saveKey));
    await settle(tester);
    expect(find.text(l10n.safeZoneAddressNotFound), findsOneWidget);
    expect(app.read(safeModeProvider).zones, hasLength(1));
  });

  testWidgets('away from home the zones lock and the note says why', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.safeZone, overrides: safeModeOverrides());

    expect(find.text(l10n.safeZoneOutside), findsOneWidget);
    expect(find.text(l10n.safeZoneItem(1)), findsOneWidget);
    expect(find.byKey(SafeZoneScreen.limitedNoteKey), findsOneWidget);
    final rename = tester.widget<IconButton>(
      find.byKey(SafeZoneScreen.renameKey(0)),
    );
    expect(rename.onPressed, isNull);
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
    for (final route in [
      AppRoutes.entityProfiles,
      AppRoutes.settingsConnections,
      AppRoutes.settingsPayments,
      AppRoutes.settingsCompany,
    ]) {
      expect(find.byKey(SettingsLink.keyOf(route)), findsNothing);
    }

    await tapVersion(tester, 9);
    expect(biometrics.reasons, isEmpty);
    await tapVersion(tester, 1);
    expect(biometrics.reasons, [l10n.safeZoneReleaseReason]);
    expect(app.read(safeModeLimitedProvider), isFalse);
    expect(find.text(released()), findsWidgets);
    expect(
      find.byKey(SettingsLink.keyOf(AppRoutes.settingsPayments)),
      findsOneWidget,
    );
    await waitForToast(tester);

    for (final route in [AppRoutes.settingsSecurity, AppRoutes.safeZone]) {
      await tester.tap(find.byKey(SettingsLink.keyOf(route)));
      await settle(tester);
    }
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
    expect(
      find.byKey(SettingsLink.keyOf(AppRoutes.settingsPayments)),
      findsOneWidget,
    );

    await tapVersion(tester, 10);

    expect(biometrics.reasons, isEmpty);
  });

  testWidgets('away from home security stays open with the mask forced on', (
    tester,
  ) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.settings,
      overrides: safeModeOverrides(),
    );

    await tester.tap(
      find.byKey(SettingsLink.keyOf(AppRoutes.settingsSecurity)),
    );
    await settle(tester);

    expect(app.location, AppRoutes.settingsSecurity);
    expect(find.text(l10n.safeZoneOutside), findsOneWidget);
    final hide = tester.widget<Switch>(
      find.descendant(
        of: find.byKey(SecuritySettingsScreen.hideAmountsKey),
        matching: find.byType(Switch),
      ),
    );
    expect(hide.value, isTrue);
    expect(hide.onChanged, isNull);
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
