import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/pix_contacts_providers.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_editor.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_labels.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/builders.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

const _draft = PixContactDraft(
  name: 'Ana',
  handle: 'ana',
  keyKind: PixKeyKind.email,
  pixKey: 'ana@exemplo.com',
);

Future<void> _fill(
  WidgetTester tester, {
  String? name,
  PixKeyKind? kind,
  String? key,
  String? handle,
}) async {
  final fields = [
    (PixContactEditor.nameKey, name),
    (PixContactEditor.pixKeyKey, key),
    (PixContactEditor.handleKey, handle),
  ];
  if (kind != null) {
    await tester.tap(find.byKey(PixContactEditor.kindKey(kind)));
    await tester.pump();
  }
  for (final (field, text) in fields) {
    if (text == null) continue;
    await tester.enterText(find.byKey(field), text);
    await tester.pump();
  }
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(PixContactEditor.saveKey));
  await settle(tester);
}

void main() {
  setUpAll(() => registerFallbackValue(_draft));

  testWidgets('lists the contacts and filters them', (tester) async {
    await pumpRoute(tester, AppRoutes.pixContacts);

    expect(find.text('Marina Exemplo'), findsOneWidget);
    expect(find.byKey(PixContactsScreen.rowKey('contact-3')), findsOneWidget);

    await tester.enterText(find.byKey(PixContactsScreen.searchKey), '@joao');
    await tester.pump();

    expect(find.text('João Fictício'), findsOneWidget);
    expect(find.text('Marina Exemplo'), findsNothing);

    await tester.enterText(find.byKey(PixContactsScreen.searchKey), 'zzz');
    await tester.pump();

    expect(find.text(l10n.pixContactsNoMatch), findsOneWidget);
  });

  testWidgets('adds a contact with a handle made from the name', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.pixContacts);
    await tester.tap(find.byKey(PixContactsScreen.addKey));
    await settle(tester);

    await _save(tester);

    expect(find.text(l10n.pixContactNameMissing), findsOneWidget);
    expect(find.text(l10n.pixContactKeyInvalid), findsOneWidget);
    expect(find.text(l10n.pixContactHandleInvalid), findsOneWidget);

    await _fill(
      tester,
      name: 'Ana Souza Exemplo',
      kind: PixKeyKind.email,
      key: 'Ana@Exemplo.com',
    );

    expect(find.text(l10n.pixContactHandleHelp('ana.exemplo')), findsOneWidget);

    await _save(tester);

    expect(find.text(l10n.pixContactSaved), findsOneWidget);
    await waitForToast(tester);
    expect(find.text('Ana Souza Exemplo'), findsOneWidget);
    expect(
      find.byKey(PixContactsScreen.rowKey('contact-new-1')),
      findsOneWidget,
    );
  });

  testWidgets('a key or handle another contact holds is caught early', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.pixContacts);
    await tester.tap(find.byKey(PixContactsScreen.addKey));
    await settle(tester);

    await _fill(
      tester,
      name: 'Outra Pessoa',
      kind: PixKeyKind.email,
      key: 'joao@exemplo.com',
      handle: 'marina',
    );
    await _save(tester);

    expect(find.text(l10n.pixContactKeyTaken), findsOneWidget);
    expect(find.text(l10n.pixContactHandleTaken), findsOneWidget);

    await _fill(
      tester,
      kind: PixKeyKind.taxId,
      key: '529.982.247-25',
      handle: 'outra',
    );
    await _save(tester);

    expect(
      find.byKey(PixContactsScreen.rowKey('contact-new-1')),
      findsOneWidget,
    );
  });

  testWidgets('edits a contact, then deletes it after asking', (tester) async {
    await pumpRoute(tester, AppRoutes.pixContacts);
    await tester.tap(find.byKey(PixContactsScreen.rowKey('contact-3')));
    await settle(tester);

    expect(find.text('diarista'), findsOneWidget);

    await _fill(tester, name: 'Diarista Nova', kind: PixKeyKind.phone);
    await _fill(tester, key: '(41) 99999-0003');
    await _save(tester);
    await waitForToast(tester);

    expect(find.text('Diarista Nova'), findsOneWidget);

    await tester.tap(find.byKey(PixContactsScreen.rowKey('contact-3')));
    await settle(tester);
    await tester.tap(find.byKey(PixContactEditor.deleteKey));
    await settle(tester);

    expect(find.text(l10n.pixContactDeleteTitle('Diarista Nova')), findsOne);

    await tester.tap(find.text(l10n.cancelButton));
    await settle(tester);
    await tester.tap(find.byKey(PixContactsScreen.rowKey('contact-3')));
    await settle(tester);
    await tester.tap(find.byKey(PixContactEditor.deleteKey));
    await settle(tester);
    await tester.tap(find.byKey(PixContactEditor.deleteKey));
    await settle(tester);

    expect(find.text(l10n.pixContactDeleted), findsOneWidget);
    expect(find.byKey(PixContactsScreen.rowKey('contact-3')), findsNothing);
  });

  group('with a mocked server', () {
    late MockPixContactsRepository repository;

    Future<void> open(WidgetTester tester) => pumpRoute(
      tester,
      AppRoutes.pixContacts,
      overrides: [pixContactsRepositoryProvider.overrideWithValue(repository)],
    );

    setUp(() => repository = MockPixContactsRepository());

    testWidgets('says when there is no contact yet', (tester) async {
      when(repository.list).thenAnswer((_) async => const Ok([]));

      await open(tester);

      expect(find.text(l10n.pixContactsEmptyTitle), findsOneWidget);
    });

    testWidgets('a list that fails can be loaded again', (tester) async {
      when(repository.list)
          .thenAnswer((_) async => const Err(NetworkFailure()));

      await open(tester);

      expect(find.text(l10n.pixContactsTitle), findsOneWidget);
      when(repository.list).thenAnswer((_) async => Ok([testContact()]));
      await tester.tap(find.text(l10n.retryButton));
      await settle(tester);

      expect(find.byKey(PixContactsScreen.rowKey('contact-1')), findsOneWidget);
    });

    testWidgets('shows what the server refused, and a failed delete', (
      tester,
    ) async {
      when(repository.list).thenAnswer((_) async => Ok([testContact()]));
      when(() => repository.update(any(), any())).thenAnswer(
        (_) async => const Err(ValidationFailure('Chave Pix inválida.')),
      );
      when(() => repository.delete(any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      await open(tester);

      await tester.tap(find.byKey(PixContactsScreen.rowKey('contact-1')));
      await settle(tester);
      await _save(tester);

      expect(find.byKey(PixContactEditor.errorKey), findsOneWidget);
      expect(find.text('Chave Pix inválida.'), findsOneWidget);

      await tester.tap(find.byKey(PixContactEditor.deleteKey));
      await settle(tester);
      await tester.tap(find.byKey(PixContactEditor.deleteKey));
      await settle(tester);

      expect(find.text(const NetworkFailure().userMessage(l10n)), findsOne);
    });
  });

  test('labels cover every key type and choice', () {
    for (final type in PixKeyType.values) {
      expect(pixKeyTypeLabel(l10n, type), isNotEmpty);
    }
    for (final kind in PixKeyKind.values) {
      expect(pixKeyKindLabel(l10n, kind), isNotEmpty);
      expect(pixKeyKindIcon(kind), isNotNull);
    }
    expect(paidLine(l10n, testContact()), l10n.pixContactPaidTimes(0));
  });
}
