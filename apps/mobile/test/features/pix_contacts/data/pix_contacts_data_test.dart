import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/pix_contacts/data/api_pix_contacts_repository.dart';
import 'package:cashdeck/features/pix_contacts/data/fake_pix_contacts_repository.dart';
import 'package:cashdeck/features/pix_contacts/data/pix_contact_dtos.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/pix_contacts_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

Map<String, dynamic> _contact({String id = 'contact-1', Object? paid}) => {
  'id': id,
  'name': 'Marina Exemplo',
  'handle': 'marina',
  'pixKey': '+5541999990001',
  'pixKeyType': 'PHONE',
  'timesPaid': 2,
  'lastPaidAt': paid,
  'createdAt': '2026-10-08T12:00:00.000Z',
};

const _draft = PixContactDraft(
  name: ' Ana Exemplo ',
  handle: 'ana',
  keyKind: PixKeyKind.email,
  pixKey: 'Ana@Exemplo.com',
);

void main() {
  group('dtos', () {
    test('read a contact and every key type', () {
      final contact = pixContactFromJson(
        _contact(paid: '2026-10-07T12:00:00.000Z'),
      );

      expect(contact.pixKeyType, PixKeyType.phone);
      expect(contact.timesPaid, 2);
      expect(contact.lastPaidAt, isNotNull);
      expect(pixContactFromJson(_contact()).lastPaidAt, isNull);
      for (final type in PixKeyType.values) {
        final json = {'type': pixKeyTypeToJson(type)};
        expect(readOptionalKeyType(json, 'type'), type);
      }
      expect(readOptionalKeyType({'type': 'NEW'}, 'type'), isNull);
      expect(readOptionalKeyType({}, 'type'), isNull);
    });

    test('a draft travels normalized, or as typed when unreadable', () {
      expect(pixContactDraftToJson(_draft), {
        'name': 'Ana Exemplo',
        'handle': 'ana',
        'pixKey': 'ana@exemplo.com',
        'pixKeyType': 'EMAIL',
      });
      expect(
        pixContactDraftToJson(
          const PixContactDraft(
            name: 'Ana',
            handle: 'ana',
            keyKind: PixKeyKind.evp,
            pixKey: ' x ',
          ),
        ),
        {'name': 'Ana', 'handle': 'ana', 'pixKey': 'x'},
      );
    });
  });

  test('the api lists, creates, updates and deletes', () async {
    final dio = stubDio((options) {
      final key = '${options.method} ${options.path}';
      return switch (key) {
        'GET /api/v1/pix-contacts' => StubResponse(200, {
          'data': [_contact()],
        }),
        'POST /api/v1/pix-contacts' => StubResponse(201, {
          'data': _contact(id: 'contact-2'),
        }),
        'PATCH /api/v1/pix-contacts/contact-1' => StubResponse(200, {
          'data': _contact(),
        }),
        'DELETE /api/v1/pix-contacts/contact-1' => const StubResponse(200, {
          'data': {'id': 'contact-1'},
        }),
        'POST /api/v1/pix-transfers/preview' => const StubResponse(200, {
          'data': {
            'contact': {
              'id': null,
              'name': 'Ana Exemplo',
              'handle': 'ana',
              'pixKey': 'ana@exemplo.com',
              'pixKeyType': 'EMAIL',
              'isNew': true,
            },
            'recipient': {
              'name': 'Ana Exemplo',
              'taxId': '***.456.789-**',
              'bank': null,
              'verified': true,
            },
          },
        }),
        'POST /api/v1/pix-transfers' => const StubResponse(201, {
          'data': {'id': 'bill-9'},
        }),
        _ => const StubResponse(404),
      };
    });
    final repository = ApiPixContactsRepository(dio);

    expect(_ok(await repository.list(search: 'mar')).single.id, 'contact-1');
    expect(_ok(await repository.create(_draft)).id, 'contact-2');
    expect(_ok(await repository.update('contact-1', _draft)).id, 'contact-1');
    expect(await repository.delete('contact-1'), isA<Ok<void>>());
    expect(await repository.delete('none'), isA<Err<void>>());

    final preview = _ok(
      await repository.preview(
        const PixPayee.newKey(_draft),
        EntityKind.company,
      ),
    );
    expect(preview.recipient.verified, isTrue);
    expect(preview.pixKeyType, PixKeyType.email);
    expect(
      await repository.send(
        const PixPayee.contact('contact-1'),
        EntityKind.personal,
        const Money(2050),
      ),
      const Ok('bill-9'),
    );

    final requests = adapterOf(dio).requests;
    expect(requests[0].queryParameters, {'search': 'mar'});
    expect((requests[1].data as Map)['pixKeyType'], 'EMAIL');
    expect(requests[5].data, {
      'name': 'Ana Exemplo',
      'pixKey': 'ana@exemplo.com',
      'pixKeyType': 'EMAIL',
      'entity': 'PJ',
    });
    expect(requests[6].data, {
      'contactId': 'contact-1',
      'entity': 'PF',
      'amountCents': 2050,
    });
  });

  group('fake', () {
    FakePixContactsRepository repository() =>
        FakePixContactsRepository(FixedClock(testNow), latency: Duration.zero);

    test('lists the most recently paid first and searches', () async {
      final fake = repository();

      final all = _ok(await fake.list());
      final found = _ok(await fake.list(search: 'joão'));

      expect(all.map((contact) => contact.handle), [
        'marina',
        'joao.ficticio',
        'diarista',
      ]);
      expect(found.single.handle, 'joao.ficticio');
    });

    test('keeps keys and handles unique', () async {
      final fake = repository();

      final created = _ok(await fake.create(_draft));
      final renamed = _ok(
        await fake.update(
          created.id,
          const PixContactDraft(
            name: 'Ana Nova',
            handle: 'ana.nova',
            keyKind: PixKeyKind.email,
            pixKey: 'ana@exemplo.com',
          ),
        ),
      );

      expect(created.pixKey, 'ana@exemplo.com');
      expect(renamed.handle, 'ana.nova');
      expect(renamed.createdAt, created.createdAt);
      expect(
        await fake.create(_draft),
        const Err<PixContact>(
          ValidationFailure('Essa chave já é de um contato.'),
        ),
      );
      expect(
        await fake.create(
          const PixContactDraft(
            name: 'Outra',
            handle: 'marina',
            keyKind: PixKeyKind.email,
            pixKey: 'outra@exemplo.com',
          ),
        ),
        const Err<PixContact>(ValidationFailure('Esse @ já está em uso.')),
      );
      expect(
        await fake.create(
          const PixContactDraft(
            name: 'X',
            handle: 'xx',
            keyKind: PixKeyKind.email,
            pixKey: 'x',
          ),
        ),
        const Err<PixContact>(ValidationFailure('Chave Pix inválida.')),
      );
      expect(
        await fake.update('none', _draft),
        const Err<PixContact>(NotFoundFailure()),
      );
      expect(await fake.delete(created.id), const Ok<void>(null));
      expect(await fake.delete(created.id), const Err<void>(NotFoundFailure()));
    });

    test('previews and sends a Pix, saving a new key as a contact', () async {
      final fake = repository();

      final known = _ok(
        await fake.preview(
          const PixPayee.contact('contact-1'),
          EntityKind.personal,
        ),
      );
      final fresh = _ok(
        await fake.preview(const PixPayee.newKey(_draft), EntityKind.personal),
      );
      expect(known.recipient.verified, isTrue);
      expect(known.isNew, isFalse);
      expect(fresh.recipient.verified, isFalse);
      expect(fresh.name, 'Ana Exemplo');
      expect(
        await fake.preview(const PixPayee.contact('none'), EntityKind.personal),
        const Err<PixPreview>(NotFoundFailure()),
      );
      const bad = PixContactDraft(
        name: 'X',
        handle: '',
        keyKind: PixKeyKind.email,
        pixKey: 'x',
      );
      expect(
        await fake.preview(const PixPayee.newKey(bad), EntityKind.personal),
        const Err<PixPreview>(ValidationFailure('Chave Pix inválida.')),
      );

      const money = Money(100);
      expect(
        await fake.send(
          const PixPayee.newKey(_draft),
          EntityKind.personal,
          money,
        ),
        const Ok('bill-condo'),
      );
      expect(_ok(await fake.list(search: 'ana')).single.handle, 'ana.exemplo');
      expect(
        await fake.send(
          const PixPayee.newKey(_draft),
          EntityKind.personal,
          money,
        ),
        const Err<String>(ValidationFailure('Essa chave já é de um contato.')),
      );
      expect(
        await fake.send(
          const PixPayee.contact('contact-1'),
          EntityKind.personal,
          money,
        ),
        const Ok('bill-condo'),
      );
    });
  });

  test('the provider picks fake or api by the backend', () {
    final fake = ProviderContainer();
    addTearDown(fake.dispose);
    final api = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://api.test'),
        ),
      ],
    );
    addTearDown(api.dispose);

    expect(
      fake.read(pixContactsRepositoryProvider),
      isA<FakePixContactsRepository>(),
    );
    expect(
      api.read(pixContactsRepositoryProvider),
      isA<ApiPixContactsRepository>(),
    );
    expect(fake.read(listPixContactsProvider), isNotNull);
    expect(fake.read(savePixContactProvider), isNotNull);
    expect(fake.read(deletePixContactProvider), isNotNull);
  });
}
