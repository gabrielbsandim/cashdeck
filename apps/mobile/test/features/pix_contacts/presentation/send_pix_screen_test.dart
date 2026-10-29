import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/features/bills/presentation/bill_detail_screen.dart';
import 'package:cashdeck/features/bills/presentation/bills_screen.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
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

Future<void> _amount(WidgetTester tester, String digits) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(CdCurrencyInput),
      matching: find.byType(TextField),
    ),
    digits,
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await settle(tester);
}

void main() {
  testWidgets('the Pay button sends a Pix to a saved contact', (tester) async {
    final biometrics = FakeBiometricAuthenticator();
    await pumpRoute(
      tester,
      AppRoutes.bills,
      overrides: [biometricAuthenticatorProvider.overrideWithValue(biometrics)],
    );

    await _tap(tester, BillsScreen.payKey);
    expect(find.text(l10n.billsPayPixHint), findsOneWidget);
    await _tap(tester, BillsScreen.payOptionKey(AppRoutes.sendPix));
    expect(find.byType(SendPixScreen), findsOneWidget);

    await _tap(tester, SendPixScreen.reviewKey);
    expect(find.text(l10n.sendPixChooseSomeone), findsOneWidget);

    await tester.enterText(find.byKey(SendPixScreen.searchKey), 'marina');
    await tester.pump();
    expect(find.byKey(SendPixScreen.contactKey('contact-2')), findsNothing);
    await _tap(tester, SendPixScreen.contactKey('contact-1'));
    await _tap(tester, SendPixScreen.reviewKey);
    expect(find.text(l10n.sendPixAmountMissing), findsOneWidget);

    await _amount(tester, '2050');
    await _tap(tester, SendPixScreen.reviewKey);
    expect(
      find.text(l10n.sendPixReviewTitle('Marina Exemplo')),
      findsOneWidget,
    );
    expect(find.text(l10n.chatRecipientVerified), findsOneWidget);
    expect(find.text('Banco Exemplo'), findsOneWidget);

    await _tap(tester, CdConfirmSheet.confirmKey);
    expect(biometrics.reasons, hasLength(1));
    expect(find.byType(BillDetailScreen), findsOneWidget);
    expect(find.text(l10n.sendPixDone), findsOneWidget);
  });

  testWidgets('a new key warns when nobody could confirm the holder', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      AppRoutes.sendPix,
      overrides: [
        biometricAuthenticatorProvider.overrideWithValue(
          FakeBiometricAuthenticator(),
        ),
      ],
    );

    await _tap(tester, SendPixScreen.newKeyKey);
    await tester.enterText(find.byKey(SendPixScreen.nameKey), 'Bia Exemplo');
    await _tap(tester, SendPixScreen.kindKey(PixKeyKind.email));
    await tester.enterText(find.byKey(SendPixScreen.pixKeyKey), 'bia@ex');
    await _amount(tester, '500');
    await _tap(tester, SendPixScreen.reviewKey);
    expect(find.text(l10n.sendPixChooseSomeone), findsOneWidget);

    await tester.enterText(
      find.byKey(SendPixScreen.pixKeyKey),
      'bia@exemplo.com',
    );
    await _tap(tester, SendPixScreen.entityKey(EntityKind.company));
    await _tap(tester, SendPixScreen.reviewKey);
    expect(find.byKey(CdConfirmSheet.warningKey), findsOneWidget);
    expect(find.text(l10n.entityCompany), findsWidgets);

    await _tap(tester, CdConfirmSheet.confirmKey);
    expect(find.byType(BillDetailScreen), findsOneWidget);
  });

  group('with a mocked server', () {
    late MockPixContactsRepository repository;

    setUpAll(() {
      registerFallbackValue(const PixPayee.contact('x'));
      registerFallbackValue(EntityKind.personal);
      registerFallbackValue(const Money(0));
    });

    setUp(() {
      repository = MockPixContactsRepository();
      when(repository.list).thenAnswer((_) async => Ok([testContact()]));
    });

    Future<void> open(WidgetTester tester) async {
      await pumpRoute(
        tester,
        AppRoutes.sendPix,
        overrides: [
          pixContactsRepositoryProvider.overrideWithValue(repository),
          biometricAuthenticatorProvider.overrideWithValue(
            FakeBiometricAuthenticator(),
          ),
        ],
      );
      await _tap(tester, SendPixScreen.contactKey(testContact().id));
      await _amount(tester, '100');
    }

    testWidgets('a lookup or a send that fails says why', (tester) async {
      when(() => repository.preview(any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      await open(tester);

      await _tap(tester, SendPixScreen.reviewKey);
      expect(find.byKey(SendPixScreen.problemKey), findsOneWidget);
      expect(find.byType(CdConfirmSheet), findsNothing);

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
      when(() => repository.send(any(), any(), any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      await _tap(tester, SendPixScreen.reviewKey);
      await _tap(tester, CdConfirmSheet.confirmKey);
      expect(find.byType(SendPixScreen), findsOneWidget);
      expect(find.text(l10n.errorNetwork), findsOneWidget);
    });

    testWidgets('a contact list that fails can be loaded again', (
      tester,
    ) async {
      when(repository.list)
          .thenAnswer((_) async => const Err(NetworkFailure()));
      await pumpRoute(
        tester,
        AppRoutes.sendPix,
        overrides: [
          pixContactsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      expect(find.text(l10n.errorNetwork), findsOneWidget);
    });
  });
}
