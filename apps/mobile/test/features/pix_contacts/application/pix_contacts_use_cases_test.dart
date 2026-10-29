import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/pix_contacts/application/pix_contacts_use_cases.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/builders.dart';
import '../../../support/mocks.dart';

const _draft = PixContactDraft(
  name: 'Ana',
  handle: 'ana',
  keyKind: PixKeyKind.email,
  pixKey: 'ana@exemplo.com',
);

void main() {
  late MockPixContactsRepository repository;

  setUpAll(() => registerFallbackValue(_draft));

  setUp(() => repository = MockPixContactsRepository());

  test('each use case forwards to the repository', () async {
    final contact = testContact();
    when(repository.list).thenAnswer((_) async => Ok([contact]));
    when(() => repository.create(_draft)).thenAnswer((_) async => Ok(contact));
    when(() => repository.update('contact-1', _draft))
        .thenAnswer((_) async => Ok(contact));
    when(() => repository.delete('contact-1'))
        .thenAnswer((_) async => const Ok(null));

    expect(await ListPixContacts(repository).call(), Ok([contact]));
    expect(await SavePixContact(repository).call(_draft), Ok(contact));
    expect(
      await SavePixContact(repository).call(_draft, id: 'contact-1'),
      Ok(contact),
    );
    expect(
      await DeletePixContact(repository).call('contact-1'),
      const Ok<void>(null),
    );
  });

  test('a draft that breaks a rule never reaches the server', () async {
    final result = await SavePixContact(repository).call(
      const PixContactDraft(
        name: '',
        handle: 'ana',
        keyKind: PixKeyKind.email,
        pixKey: 'ana@exemplo.com',
      ),
    );

    expect(result, const Err<PixContact>(UnexpectedFailure()));
    verifyNever(() => repository.create(any()));
  });

  test('a Pix is previewed and sent, never for nothing', () async {
    const payee = PixPayee.contact('contact-1');
    const preview = PixPreview(
      name: 'Ana',
      pixKey: 'ana@exemplo.com',
      pixKeyType: PixKeyType.email,
      isNew: false,
      recipient: PixRecipientCheck(name: 'Ana', verified: true),
    );
    when(() => repository.preview(payee, EntityKind.personal))
        .thenAnswer((_) async => const Ok(preview));
    when(() => repository.send(payee, EntityKind.personal, const Money(100)))
        .thenAnswer((_) async => const Ok('bill-1'));

    expect(
      await PreviewPixTransfer(repository).call(payee, EntityKind.personal),
      const Ok(preview),
    );
    expect(
      await SendPixTransfer(repository)
          .call(payee, EntityKind.personal, const Money(100)),
      const Ok('bill-1'),
    );
    expect(
      await SendPixTransfer(repository)
          .call(payee, EntityKind.personal, const Money(0)),
      const Err<String>(UnexpectedFailure()),
    );
    expect(preview.props, hasLength(5));
    expect(preview.recipient.props, hasLength(4));
    expect(payee.props, ['contact-1', null]);
  });
}
