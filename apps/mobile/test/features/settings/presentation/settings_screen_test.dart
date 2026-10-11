import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/features/automation/automation_providers.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:cashdeck/features/automation/presentation/automation_controller.dart';
import 'package:cashdeck/features/settings/presentation/sections/payments_settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/sections/security_settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/settings_screen.dart';
import 'package:cashdeck/features/settings/presentation/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

void main() {
  testWidgets('the hub lists one row per group and the version', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.settings);

    for (final section in SettingsSection.values) {
      expect(find.text(section.title(l10n)), findsOneWidget);
      expect(find.text(section.hint(l10n)), findsOneWidget);
    }
    expect(find.text(l10n.settingsVersion(testVersion)), findsOneWidget);
    expect(find.byKey(SettingsScreen.signOutKey), findsOneWidget);
    expect(find.byKey(PaymentsSettingsScreen.pauseKey), findsNothing);
  });

  final links = {
    AppRoutes.settings: [
      AppRoutes.entityProfiles,
      AppRoutes.settingsConnections,
      AppRoutes.settingsPayments,
      AppRoutes.settingsCompany,
      AppRoutes.settingsSecurity,
      AppRoutes.alertSettings,
    ],
    AppRoutes.settingsConnections: [
      AppRoutes.connectItemId,
      AppRoutes.captureSources,
      AppRoutes.cardImport,
      AppRoutes.cardNotifications,
    ],
    AppRoutes.settingsPayments: [AppRoutes.rails],
    AppRoutes.settingsCompany: [
      AppRoutes.invoiceIssuer,
      AppRoutes.payroll,
      AppRoutes.accountantExport,
    ],
    AppRoutes.settingsSecurity: [AppRoutes.safeZone],
  };
  for (final MapEntry(key: from, value: routes) in links.entries) {
    for (final route in routes) {
      testWidgets('$from opens $route', (tester) async {
        final app = await pumpRoute(
          tester,
          from,
          overrides: [
            biometricAuthenticatorProvider.overrideWithValue(
              FakeBiometricAuthenticator(approve: false),
            ),
          ],
        );

        await tester.tap(find.byKey(SettingsLink.keyOf(route)));
        await settle(tester);

        expect(app.location, route);
      });
    }
  }

  testWidgets('each group screen says what it holds', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.settingsConnections);
    expect(find.text(l10n.settingsConnectionsIntro), findsOneWidget);

    for (final (route, intro) in [
      (AppRoutes.settingsPayments, l10n.settingsPaymentsIntro),
      (AppRoutes.settingsCompany, l10n.settingsCompanyIntro),
      (AppRoutes.settingsSecurity, l10n.settingsSecurityIntro),
    ]) {
      app.router.go(route);
      await settle(tester);
      expect(find.text(intro), findsOneWidget, reason: route);
    }
  });

  testWidgets('toggles the privacy mode', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.settingsSecurity);

    await tester.tap(find.byKey(SecuritySettingsScreen.hideAmountsKey));
    await settle(tester);
    expect(
      app.read(displayPreferencesProvider),
      const DisplayPreferences(hideAmounts: true),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(SecuritySettingsScreen.hideAmountsKey),
        matching: find.byType(Switch),
      ),
    );
    await settle(tester);
    expect(app.read(displayPreferencesProvider).hideAmounts, isFalse);
  });

  testWidgets('the kill switch pauses every automatic payment', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.settingsPayments);

    await tester.tap(
      find.descendant(
        of: find.byKey(PaymentsSettingsScreen.pauseKey),
        matching: find.byType(Switch),
      ),
    );
    await settle(tester);

    expect(app.read(automationControllerProvider).value?.paused, isTrue);
  });

  testWidgets('a failed pause says why', (tester) async {
    final automation = MockAutomationRepository();
    when(automation.status)
        .thenAnswer((_) async => const Ok(AutomationStatus()));
    when(automation.pause).thenAnswer((_) async => const Err(NetworkFailure()));
    await pumpRoute(
      tester,
      AppRoutes.settingsPayments,
      overrides: [automationRepositoryProvider.overrideWithValue(automation)],
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(PaymentsSettingsScreen.pauseKey),
        matching: find.byType(Switch),
      ),
    );
    await settle(tester);

    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });
}
