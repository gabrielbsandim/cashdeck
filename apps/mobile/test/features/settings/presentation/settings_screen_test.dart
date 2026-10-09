import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/features/automation/automation_providers.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:cashdeck/features/automation/presentation/automation_controller.dart';
import 'package:cashdeck/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

void main() {
  testWidgets('changes the theme and the privacy mode', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.settings);

    await tester.tap(find.text(l10n.themeDark));
    await settle(tester);
    await tester.tap(find.byKey(SettingsScreen.hideAmountsKey));
    await settle(tester);
    expect(
      app.read(displayPreferencesProvider),
      const DisplayPreferences(themeMode: ThemeMode.dark, hideAmounts: true),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(SettingsScreen.hideAmountsKey),
        matching: find.byType(Switch),
      ),
    );
    await settle(tester);
    expect(app.read(displayPreferencesProvider).hideAmounts, isFalse);
  });

  testWidgets('the kill switch pauses every automatic payment', (tester) async {
    final app = await pumpRoute(tester, AppRoutes.settings);

    await tester.tap(
      find.descendant(
        of: find.byKey(SettingsScreen.pauseKey),
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
      AppRoutes.settings,
      overrides: [automationRepositoryProvider.overrideWithValue(automation)],
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(SettingsScreen.pauseKey),
        matching: find.byType(Switch),
      ),
    );
    await settle(tester);

    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });

  for (final route in [
    AppRoutes.entityProfiles,
    AppRoutes.rails,
    AppRoutes.captureSources,
    AppRoutes.cardImport,
    AppRoutes.connectItemId,
    AppRoutes.invoiceIssuer,
    AppRoutes.payroll,
    AppRoutes.accountantExport,
    AppRoutes.unlock,
  ]) {
    testWidgets('opens $route', (tester) async {
      final app = await pumpRoute(
        tester,
        AppRoutes.settings,
        overrides: [
          biometricAuthenticatorProvider.overrideWithValue(
            FakeBiometricAuthenticator(approve: false),
          ),
        ],
      );

      await tester.tap(find.byKey(SettingsScreen.rowKey(route)));
      await settle(tester);

      expect(app.location, route);
    });
  }
}
