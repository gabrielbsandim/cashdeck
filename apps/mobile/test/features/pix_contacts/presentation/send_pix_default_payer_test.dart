import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/pix_contacts_providers.dart';
import 'package:cashdeck/features/pix_contacts/presentation/send_pix_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await settle(tester);
}

void main() {
  late MockPixContactsRepository repository;

  setUpAll(() {
    registerFallbackValue(const PixPayee.contact('x'));
    registerFallbackValue(EntityKind.personal);
    registerFallbackValue(const Money(0));
  });

  setUp(() {
    repository = MockPixContactsRepository();
    when(repository.list).thenAnswer((_) async => Ok([testContact()]));
    when(() => repository.preview(any(), any())).thenAnswer(
      (_) async => const Ok(
        PixPreview(
          name: 'Ana',
          pixKey: '+5541999990000',
          pixKeyType: PixKeyType.phone,
          isNew: false,
          recipient: PixRecipientCheck(name: 'Ana', verified: true),
        ),
      ),
    );
  });

  testWidgets('criterion 4: send Pix starts on PF with the switcher on PJ', (
    tester,
  ) async {
    final app = await pumpRoute(
      tester,
      AppRoutes.home,
      overrides: [
        pixContactsRepositoryProvider.overrideWithValue(repository),
        biometricAuthenticatorProvider.overrideWithValue(
          FakeBiometricAuthenticator(),
        ),
      ],
    );
    app.read(entityScopeProvider.notifier).select(EntityScope.company);
    await tester.pump();
    app.router.go(AppRoutes.sendPix);
    await settle(tester);

    await _tap(tester, SendPixScreen.contactKey(testContact().id));
    await tester.enterText(
      find.descendant(
        of: find.byType(CdCurrencyInput),
        matching: find.byType(TextField),
      ),
      '100',
    );
    await tester.pump();
    await _tap(tester, SendPixScreen.reviewKey);

    Finder inSheet(String text) => find.descendant(
      of: find.byType(CdConfirmSheet),
      matching: find.text(text),
    );
    expect(inSheet(l10n.sendPixFrom), findsOneWidget);
    expect(inSheet(l10n.entityPersonal), findsOneWidget);
    expect(inSheet(l10n.entityCompany), findsNothing);
    verify(() => repository.preview(any(), EntityKind.personal)).called(1);
  });
}
