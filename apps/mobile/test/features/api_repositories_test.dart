import 'dart:convert';
import 'dart:typed_data';

import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/file_transfer.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/accountant_export/accountant_export_providers.dart';
import 'package:cashdeck/features/accountant_export/data/api_accountant_export_repository.dart';
import 'package:cashdeck/features/accountant_export/domain/accountant_export.dart';
import 'package:cashdeck/features/automation/automation_providers.dart';
import 'package:cashdeck/features/automation/data/api_automation_repository.dart';
import 'package:cashdeck/features/automation/domain/automation.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/data/api_capture_repository.dart';
import 'package:cashdeck/features/capture/data/upload_fit.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/card_import/card_import_providers.dart';
import 'package:cashdeck/features/card_import/data/api_card_import_repository.dart';
import 'package:cashdeck/features/card_import/domain/card_statement.dart';
import 'package:cashdeck/features/entities/data/entity_dtos.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/data/api_home_repository.dart';
import 'package:cashdeck/features/home/data/home_dtos.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/home_providers.dart';
import 'package:cashdeck/features/invoices/data/api_issuer_repository.dart';
import 'package:cashdeck/features/invoices/domain/issuer_setup.dart';
import 'package:cashdeck/features/invoices/invoices_providers.dart';
import 'package:cashdeck/features/open_finance/data/api_open_finance_repository.dart';
import 'package:cashdeck/features/open_finance/domain/item_lookup.dart';
import 'package:cashdeck/features/open_finance/open_finance_providers.dart';
import 'package:cashdeck/features/payroll/data/api_payroll_repository.dart';
import 'package:cashdeck/features/payroll/domain/payroll.dart';
import 'package:cashdeck/features/payroll/payroll_providers.dart';
import 'package:cashdeck/features/rails/data/api_rails_repository.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:cashdeck/features/rails/rails_providers.dart';
import 'package:cashdeck/features/receipts/data/api_receipts_repository.dart';
import 'package:cashdeck/features/receipts/domain/receipt.dart';
import 'package:cashdeck/features/receipts/receipts_providers.dart';
import 'package:cashdeck/features/transactions/data/api_transfers_repository.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_adapter.dart';

JsonMap _money(int cents, [String currency = 'BRL']) => {
  'cents': cents,
  'currency': currency,
};

/// Routes by "METHOD path"; anything unrouted answers 404.
Dio _api(Map<String, Object?> routes) => stubDio((options) {
  final key = '${options.method} ${options.path}';
  if (!routes.containsKey(key)) return const StubResponse(404);
  final body = routes[key];
  if (body is StubResponse) return body;
  return StubResponse(200, {'data': body});
});

List<String> _calls(Dio dio) => [
  for (final request in adapterOf(dio).requests)
    '${request.method} ${request.path}',
];

JsonMap _sent(Dio dio, int index) =>
    adapterOf(dio).requests[index].data as JsonMap;

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

final _pfx = LocalFile(name: 'cert.pfx', bytes: Uint8List.fromList([1, 2, 3]));

final JsonMap _company = {
  'cash': _money(100),
  'sync': {'accountCount': 2, 'syncedAt': null},
  'billed': _money(50),
  'invoiceCount': 1,
  'dasEstimate': _money(5),
  'dasDue': '2026-11-20',
  'inss': {'estimate': _money(2), 'due': '2026-10-20'},
  'annex': 'III',
  'drafts': [
    {
      'id': 'd1',
      'customer': 'Cliente Exemplo',
      'amount': _money(10),
      'recurring': true,
      'issueOn': '2026-10-10',
    },
  ],
  'unbilled': [
    {
      'id': 't1',
      'payer': 'Pagador Exemplo',
      'amount': _money(20),
      'receivedOn': '2026-10-01',
    },
  ],
};

final JsonMap _credentials = {
  'certificateName': 'cert.pfx',
  'certificateValidUntil': '2027-03-02',
  'apiKeyHint': 'ab12',
  'lastTestAt': '2026-10-08T12:00:00.000Z',
};

final JsonMap _sources = {
  'mailboxes': [
    {
      'id': 'm1',
      'address': 'contas@exemplo.com',
      'owner': 'PF',
      'lastReadAt': null,
      'billsFound': 2,
      'emailsScanned': 40,
    },
  ],
  'dda': [
    {
      'owner': 'PJ',
      'bank': 'Banco Exemplo',
      'lastBatchAt': '2026-10-08T09:00:00.000Z',
      'boletos': 1,
      'enabled': false,
    },
  ],
};

final JsonMap _issuer = {
  'kind': 'MUNICIPAL',
  'city': 'Cidade Exemplo',
  'certificateName': null,
  'certificateExpiresOn': null,
  'certificateState': null,
  'municipalRegistration': '123',
  'serviceCode': {'code': '01.07', 'description': 'Suporte'},
};

final JsonMap _sheet = {
  'current': {
    'month': '2026-10-01',
    'proLabore': _money(150000),
    'salaries': _money(0),
    'fgts': _money(0),
  },
  'history': <Object?>[],
  'revenue12': _money(1000000),
};

final JsonMap _statement = {
  'id': 's1',
  'entityKind': 'PF',
  'card': 'Cartão Exemplo',
  'issuer': 'Banco Exemplo',
  'closing': '2026-10-05',
  'due': '2026-10-15',
  'rate': 54210,
  'iofBps': 350,
  'paymentCode': null,
  'lines': [
    {
      'id': 'l1',
      'merchant': 'Loja Exemplo',
      'date': '2026-09-30',
      'amount': _money(1000, 'USD'),
      'needsReview': false,
    },
  ],
  'billId': null,
};

final JsonMap _record = {
  'id': 'e1',
  'month': '2026-09-01',
  'sentOn': '2026-10-05',
  'to': null,
  'downloadPath': '/api/v1/accountant-export/e1/download',
};

void main() {
  group('core wire helpers', () {
    test('reads optional values, booleans, enums and money', () {
      final json = <String, dynamic>{
        'n': null,
        'i': 3,
        'b': true,
        'm': _money(7, 'USD'),
        'd': '2026-10-08',
        't': '2026-10-08T15:00:00Z',
        'e': 'A',
        'o': {'x': 1},
      };

      expect(readOptionalInt(json, 'n'), isNull);
      expect(readOptionalInt(json, 'i'), 3);
      expect(() => readOptionalInt(json, 'b'), throwsFormatException);
      expect(readBool(json, 'b'), isTrue);
      expect(() => readBool(json, 'i'), throwsFormatException);
      expect(readMoney(json, 'm'), const Money(7, currency: 'USD'));
      expect(readOptionalDate(json, 'n'), isNull);
      expect(readOptionalDate(json, 'd'), const CalendarDate(2026, 10, 8));
      expect(readOptionalDateTime(json, 'n'), isNull);
      expect(readOptionalDateTime(json, 't'), DateTime.utc(2026, 10, 8, 15));
      expect(readEnum(json, 'e', const {'A': 1}), 1);
      expect(() => readEnum(json, 'e', const {'B': 1}), throwsFormatException);
      expect(readOptionalMap(json, 'n'), isNull);
      expect(readOptionalMap(json, 'o'), {'x': 1});
    });

    test('a typed date must exist on the calendar', () {
      expect(
        CalendarDate.tryParseDisplay(' 02/03/2027 '),
        const CalendarDate(2027, 3, 2),
      );
      expect(CalendarDate.tryParseDisplay('31/02/2027'), isNull);
      expect(CalendarDate.tryParseDisplay('2027-03-02'), isNull);
    });

    test('a file names its type from the extension when it must', () {
      LocalFile named(String name, [String? mime]) =>
          LocalFile(name: name, bytes: Uint8List(0), mimeType: mime);

      expect(named('a.PDF').contentType, 'application/pdf');
      expect(named('a.pfx').contentType, 'application/x-pkcs12');
      expect(named('a.bin').contentType, 'application/octet-stream');
      expect(named('a.pdf', 'image/png').contentType, 'image/png');
    });

    test('uploads are base64 and downloads keep the server name', () async {
      expect(uploadBody(_pfx), {
        'fileName': 'cert.pfx',
        'mimeType': 'application/x-pkcs12',
        'base64': base64Encode([1, 2, 3]),
      });
      expect(fileNameOf(null), isNull);
      expect(fileNameOf('attachment; filename="a b.zip"'), 'a b.zip');
      expect(fileNameOf('inline'), isNull);

      final dio = stubDio(
        (_) => StubResponse(200, Uint8List.fromList([9]), {
          'content-disposition': ['attachment; filename="x.zip"'],
          'content-type': ['application/zip'],
        }),
      );
      final file = await downloadFile(dio, '/f', fallbackName: 'y.zip');
      expect(file.name, 'x.zip');
      expect(file.mimeType, 'application/zip');
      expect(file.bytes, [9]);

      final bare = stubDio((_) => StubResponse(200, Uint8List(0)));
      expect(
        (await downloadFile(bare, '/f', fallbackName: 'y.zip')).name,
        'y.zip',
      );
    });

    test('entity kinds travel as PF and PJ', () {
      expect(entityKindToJson(EntityKind.personal), 'PF');
      expect(entityKindToJson(EntityKind.company), 'PJ');
      expect(entityKindFromJson('PJ'), EntityKind.company);
      expect(() => entityKindFromJson('XX'), throwsFormatException);
    });
  });

  group('ApiHomeRepository', () {
    test('reads the summaries and posts the company actions', () async {
      final dio = _api({
        'GET /api/v1/home/personal': {
          'balance': _money(1000),
          'sync': {'accountCount': 3, 'syncedAt': '2026-10-08T14:56:00.000Z'},
          'reserve': null,
          'forecast': {
            'from': '2026-10-08',
            'balances': [_money(1000), _money(900)],
            'floor': _money(0),
          },
          'budgets': [
            {'category': 'transport', 'spent': _money(10), 'limit': _money(20)},
            {'category': 'pets', 'spent': _money(30), 'limit': _money(20)},
          ],
          'alerts': [
            {
              'type': 'ASSISTED_PAYMENT',
              'at': '2026-10-08T12:00:00.000Z',
              'billId': 'b1',
              'payee': 'Aluguel',
              'reason': 'DAILY_CAP_EXCEEDED',
            },
            {
              'type': 'BUDGET_EXCEEDED',
              'at': '2026-10-08T12:00:00.000Z',
              'budget': {
                'category': 'pets',
                'spent': _money(30),
                'limit': _money(20),
              },
            },
            {'type': 'SOMETHING_NEW'},
          ],
        },
        'GET /api/v1/home/company': _company,
        'GET /api/v1/home/consolidated': {
          'personal': _money(10),
          'company': _money(20),
          'externalIn': _money(5),
          'externalOut': _money(-3),
          'transfers': [
            {
              'id': 'x1',
              'kind': 'PRO_LABORE',
              'amount': _money(4),
              'on': '2026-10-01',
            },
          ],
        },
        'POST /api/v1/home/company/drafts/d%201/approve': _company,
        'POST /api/v1/home/company/unbilled/t1/invoice': _company,
      });
      final repository = ApiHomeRepository(dio);

      final personal = _ok(await repository.personal());
      expect(personal.reserve, isNull);
      expect(personal.forecast.balances, hasLength(2));
      expect(personal.budgets.last.category, BudgetCategory.other);
      expect(personal.budgets.last.name, 'pets');
      expect(personal.alerts, hasLength(2));
      expect(
        (personal.alerts.first as AssistedPaymentAlert).reason,
        'DAILY_CAP_EXCEEDED',
      );
      final company = _ok(await repository.company());
      expect(company.sync.syncedAt, isNull);
      expect(company.drafts.single.recurring, isTrue);
      expect(company.inss?.due, const CalendarDate(2026, 10, 20));
      final consolidated = _ok(await repository.consolidated());
      expect(
        consolidated.transfers.single.kind,
        InternalTransferKind.proLabore,
      );
      expect(await repository.approveDraft('d 1'), isA<Ok<CompanySummary>>());
      expect(await repository.issueInvoiceFor('t1'), isA<Ok<CompanySummary>>());
    });

    test('a reserve without a CDI rate keeps it null', () {
      final reserve = reserveFromJson({
        'accountId': 'a1',
        'institution': 'Banco Exemplo',
        'product': 'CDB',
        'balance': _money(1),
        'monthYield': _money(1),
        'coverDays': 12,
        'cdiPercent': null,
      });

      expect(reserve?.coverDays, 12);
      expect(reserve?.cdiPercent, isNull);
    });
  });

  group('ApiRailsRepository', () {
    test('lists, authorizes, tests and removes rails', () async {
      final rail = {
        'id': 'PF.ASAAS.PIX_API',
        'railId': 'ASAAS',
        'kind': 'PIX_API',
        'owner': 'PF',
        'step': 1,
        'institution': 'Banco Exemplo',
        'status': 'NEEDS_AUTHORIZATION',
        'configurable': true,
      };
      final dio = _api({
        'GET /api/v1/rails': [rail],
        'POST /api/v1/rails/PF.ASAAS.PIX_API/authorize': {
          ...rail,
          'status': 'ACTIVE',
        },
        'POST /api/v1/rails/PF.ASAAS.PIX_API/test': {
          'checks': [
            {'kind': 'CERTIFICATE', 'passed': true, 'millis': 40},
            {'kind': 'PAYER_ACCOUNT', 'passed': false, 'millis': null},
          ],
          'testedAt': '2026-10-08T12:00:00.000Z',
        },
        'DELETE /api/v1/rails/PF.ASAAS.PIX_API': {'id': 'PF.ASAAS.PIX_API'},
      });
      final repository = ApiRailsRepository(dio);

      final rails = _ok(await repository.rails(EntityKind.personal));
      expect(rails.single.kind, RailKind.pixApi);
      expect(adapterOf(dio).requests.first.queryParameters, {'entity': 'PF'});
      expect(
        _ok(await repository.authorize('PF.ASAAS.PIX_API')).status,
        RailStatus.active,
      );
      final checks = _ok(await repository.test('PF.ASAAS.PIX_API'));
      expect(checks.last.millis, isNull);
      expect(await repository.remove('PF.ASAAS.PIX_API'), isA<Ok<void>>());
    });

    test('missing credentials read as none, other errors pass', () async {
      final empty = ApiRailsRepository(_api({}));
      expect(await empty.credentials('r'), const Ok(RailCredentials.none));

      final broken = ApiRailsRepository(
        _api({'GET /api/v1/rails/r/credentials': const StubResponse(500)}),
      );
      expect(
        await broken.credentials('r'),
        const Err<RailCredentials>(ServerFailure()),
      );

      final stored = ApiRailsRepository(
        _api({'GET /api/v1/rails/r/credentials': _credentials}),
      );
      expect(
        _ok(await stored.credentials('r')).certificateValidUntil,
        const CalendarDate(2027, 3, 2),
      );
    });

    test('a pfx carries password and expiry, a .key is the key', () async {
      final dio = _api({'PUT /api/v1/rails/r/credentials': _credentials});
      final repository = ApiRailsRepository(dio);

      await repository.uploadCredential(
        'r',
        _pfx,
        password: 'senha',
        validUntil: const CalendarDate(2027, 3, 2),
      );
      await repository.uploadCredential(
        'r',
        LocalFile(name: 'client.key', bytes: Uint8List(1)),
        password: '',
      );

      expect(_sent(dio, 0).keys, [
        'certificate',
        'certificatePassword',
        'certificateValidUntil',
      ]);
      expect(_sent(dio, 0)['certificateValidUntil'], '2027-03-02');
      expect(_sent(dio, 1).keys, ['privateKey']);
    });
  });

  group('ApiCaptureRepository', () {
    test('reads and changes the capture sources', () async {
      final dio = _api({
        'GET /api/v1/capture/sources': _sources,
        'POST /api/v1/capture/mailboxes/m1/read': _sources,
        'DELETE /api/v1/capture/mailboxes/m1': _sources,
        'PUT /api/v1/capture/dda/PJ': _sources,
        'POST /api/v1/capture/mailboxes/oauth/start': {
          'url': 'https://consent.example.com/auth?x=1',
        },
      });
      final repository = ApiCaptureRepository(dio);

      final sources = _ok(await repository.sources());
      expect(sources.mailboxes.single.lastReadAt, isNull);
      expect(sources.dda.single.owner, EntityKind.company);
      await repository.readNow('m1');
      await repository.disconnect('m1');
      await repository.setDda(EntityKind.company, on: true);
      expect(_sent(dio, 3), {'enabled': true});
      final url = _ok(
        await repository.mailboxAuthorizationUrl(EntityKind.personal),
      );
      expect(url.host, 'consent.example.com');
      expect(_sent(dio, 4), {'entity': 'PF'});
    });

    final entities = [
      {'id': 'personal', 'kind': 'PF', 'name': 'Pessoal'},
      {'id': 'company', 'kind': 'PJ', 'name': 'Empresa'},
    ];

    test('a code becomes a bill on the entity id', () async {
      final dio = _api({
        'GET /api/v1/entities': entities,
        'POST /api/v1/bills': const StubResponse(201, {
          'data': {'id': 'b1'},
        }),
      });
      final repository = ApiCaptureRepository(dio);

      final captured = await repository.capture(
        const BillDraft(
          owner: EntityKind.personal,
          channel: CaptureChannel.camera,
          pixCode: '000201',
        ),
      );
      await repository.capture(
        const BillDraft(
          owner: EntityKind.company,
          channel: CaptureChannel.manual,
          paymentCode: '123',
          pixCode: '000201',
          amount: Money(990),
          dueDate: CalendarDate(2026, 10, 9),
          payee: ' Escola Exemplo ',
        ),
      );
      await repository.capture(
        const BillDraft(
          owner: EntityKind.personal,
          channel: CaptureChannel.share,
          pixKey: 'contas@exemplo.com',
          payee: ' ',
        ),
      );

      expect(captured, const Ok<CaptureOutcome>(BillCaptured(billId: 'b1')));
      expect(_calls(dio), [
        'GET /api/v1/entities',
        'POST /api/v1/bills',
        'POST /api/v1/bills',
        'POST /api/v1/bills',
      ]);
      expect(_sent(dio, 1), {
        'entityId': 'personal',
        'source': 'CAMERA',
        'pixCode': '000201',
      });
      expect(_sent(dio, 2), {
        'entityId': 'company',
        'source': 'MANUAL',
        'paymentCode': '123',
        'pixCode': '000201',
        'amountCents': 990,
        'dueDate': '2026-10-09',
        'payee': 'Escola Exemplo',
      });
      expect(_sent(dio, 3), {
        'entityId': 'personal',
        'source': 'SHARE',
        'pixKey': 'contas@exemplo.com',
      });
    });

    test('a duplicate answers 200 and keeps the first bill', () async {
      final repository = ApiCaptureRepository(
        _api({
          'GET /api/v1/entities': entities,
          'POST /api/v1/bills': {'id': 'b0'},
        }),
      );

      expect(
        await repository.capture(
          const BillDraft(
            owner: EntityKind.personal,
            channel: CaptureChannel.camera,
            paymentCode: '1',
          ),
        ),
        const Ok<CaptureOutcome>(BillCaptured(billId: 'b0', duplicate: true)),
      );
    });

    test(
      'the server asking for the amount or the date is an outcome',
      () async {
        StubResponse error(int status, String code) => StubResponse(status, {
          'error': {'code': code, 'message': 'x'},
        });
        Future<Result<CaptureOutcome>> answer(StubResponse response) =>
            ApiCaptureRepository(
              _api({
                'GET /api/v1/entities': entities,
                'POST /api/v1/bills': response,
              }),
            ).capture(
              const BillDraft(
                owner: EntityKind.personal,
                channel: CaptureChannel.camera,
                pixCode: '000201',
              ),
            );

        expect(
          await answer(error(422, 'AMOUNT_REQUIRED')),
          const Ok<CaptureOutcome>(CaptureDetailsNeeded(amount: true)),
        );
        expect(
          await answer(error(422, 'DUE_DATE_REQUIRED')),
          const Ok<CaptureOutcome>(CaptureDetailsNeeded(amount: false)),
        );
        expect(
          await answer(error(422, 'VALIDATION_ERROR')),
          const Err<CaptureOutcome>(ValidationFailure('x')),
        );
        expect(
          await answer(const StubResponse(422, 'texto')),
          const Err<CaptureOutcome>(UnexpectedFailure()),
        );
        expect(
          await answer(const StubResponse(422, {'error': 'x'})),
          const Err<CaptureOutcome>(UnexpectedFailure()),
        );
      },
    );

    test('a shared file goes up as base64 with the entity', () async {
      final dio = _api({
        'POST /api/v1/capture/files': const StubResponse(201, {
          'data': {'id': 'b2'},
        }),
      });
      final repository = ApiCaptureRepository(dio);
      final pdf = LocalFile(
        name: 'conta.pdf',
        bytes: Uint8List.fromList([1, 2]),
        mimeType: 'application/pdf',
      );

      expect(
        await repository.submitFile(pdf, EntityKind.company),
        const Ok<CaptureOutcome>(BillCaptured(billId: 'b2')),
      );
      expect(_sent(dio, 0), {
        'fileName': 'conta.pdf',
        'mimeType': 'application/pdf',
        'base64': base64Encode([1, 2]),
        'entity': 'PJ',
      });
    });

    test('a file the server cannot take or read is an outcome', () async {
      Future<Result<CaptureOutcome>> answer(StubResponse response) =>
          ApiCaptureRepository(_api({'POST /api/v1/capture/files': response}))
              .submitFile(
                LocalFile(name: 'conta.pdf', bytes: Uint8List(3)),
                EntityKind.personal,
              );

      expect(
        await answer(const StubResponse(413)),
        const Ok<CaptureOutcome>(CaptureFileTooLarge(3)),
      );
      expect(
        await answer(
          const StubResponse(422, {
            'error': {'code': 'VALIDATION_ERROR', 'message': 'No code'},
          }),
        ),
        const Ok<CaptureOutcome>(CaptureNothingFound()),
      );
      expect(
        await answer(
          const StubResponse(422, {
            'error': {
              'code': 'AMOUNT_REQUIRED',
              'message': 'No amount',
              'details': {'field': 'amountCents', 'kind': 'PIX_QR'},
            },
          }),
        ),
        const Ok<CaptureOutcome>(CaptureDetailsNeeded(amount: true)),
      );
      expect(
        await answer(const StubResponse(500)),
        const Err<CaptureOutcome>(ServerFailure()),
      );
    });

    test('a file goes again with the amount and due date asked', () async {
      final dio = _api({
        'POST /api/v1/capture/files': const StubResponse(201, {
          'data': {'id': 'b4'},
        }),
      });

      await ApiCaptureRepository(dio).submitFile(
        LocalFile(name: 'conta.pdf', bytes: Uint8List(3)),
        EntityKind.personal,
        amount: const Money(4590),
        dueDate: const CalendarDate(2026, 10, 8),
      );

      expect(_sent(dio, 0)['amountCents'], 4590);
      expect(_sent(dio, 0)['dueDate'], '2026-10-08');
    });

    test('a file over the cap is refused before sending', () async {
      final dio = _api({});
      final repository = ApiCaptureRepository(dio);

      expect(
        await repository.submitFile(
          LocalFile(name: 'grande.pdf', bytes: Uint8List(maxUploadBytes + 1)),
          EntityKind.personal,
        ),
        const Ok<CaptureOutcome>(CaptureFileTooLarge(maxUploadBytes + 1)),
      );
      expect(_calls(dio), isEmpty);
    });

    test('a big photo is shrunk to JPEG before it goes up', () async {
      final dio = _api({
        'POST /api/v1/capture/files': {'id': 'b3'},
      });
      final repository = ApiCaptureRepository(
        dio,
        shrink: (_) async => Uint8List.fromList([9]),
      );

      await repository.submitFile(
        LocalFile(name: 'foto.heic', bytes: Uint8List(shrinkAbove + 1)),
        EntityKind.personal,
      );

      expect(_sent(dio, 0)['fileName'], 'foto.jpg');
      expect(_sent(dio, 0)['mimeType'], 'image/jpeg');
      expect(_sent(dio, 0)['base64'], base64Encode([9]));
    });

    test('a missing entity is not sent', () async {
      final repository = ApiCaptureRepository(
        _api({'GET /api/v1/entities': <Object?>[]}),
      );

      expect(
        await repository.capture(
          const BillDraft(
            owner: EntityKind.company,
            channel: CaptureChannel.camera,
            paymentCode: '8',
          ),
        ),
        const Err<CaptureOutcome>(UnexpectedFailure()),
      );
    });
  });

  group('ApiReceiptsRepository', () {
    final receipt = {
      'billId': 'b1',
      'proof': {
        'rail': 'ASAAS',
        'amount': _money(100),
        'paidAt': '2026-10-08T12:00:00.000Z',
        'payer': 'Pagador Exemplo',
        'receiver': 'Recebedor Exemplo',
        'transactionId': null,
        'authentication': 'AUTH1',
      },
      'attachments': [
        {
          'id': 'a1',
          'fileName': 'comprovante.pdf',
          'mimeType': 'application/pdf',
          'bytes': 3,
        },
      ],
    };

    test('reads, attaches and downloads the rendered receipt', () async {
      final dio = _api({
        'GET /api/v1/bills/b1/receipt': receipt,
        'POST /api/v1/bills/b1/attachments': {'id': 'a2'},
        'GET /api/v1/bills/b1/receipt/pdf': StubResponse(
          200,
          Uint8List.fromList([1]),
          const {
            'content-disposition': ['attachment; filename="recibo-b1.pdf"'],
          },
        ),
      });
      final repository = ApiReceiptsRepository(dio);

      final read = _ok(await repository.receipt('b1'));
      expect(read.proof?.transactionId, isNull);
      expect(read.attachments.single.fileName, 'comprovante.pdf');
      expect(await repository.attach('b1', _pfx), isA<Ok<Receipt>>());
      expect(_ok(await repository.document('b1')).name, 'recibo-b1.pdf');
    });

    test('an open bill has no receipt yet; the name falls back', () async {
      final open = ApiReceiptsRepository(
        _api({
          'GET /api/v1/bills/b1/receipt/pdf': const StubResponse(422, {
            'error': {'code': 'VALIDATION_ERROR', 'message': 'Not paid yet'},
          }),
          'GET /api/v1/bills/b2/receipt/pdf': StubResponse(
            200,
            Uint8List.fromList([2]),
          ),
        }),
      );
      expect(
        await open.document('b1'),
        const Err<LocalFile>(UnexpectedFailure()),
      );
      expect(_ok(await open.document('b2')).name, 'comprovante-b2.pdf');
    });
  });

  group('ApiIssuerRepository', () {
    test('reads, saves, tests and uploads the issuer', () async {
      final dio = _api({
        'GET /api/v1/invoices/issuer': _issuer,
        'GET /api/v1/invoices/service-codes': [
          {'code': '01.07', 'description': 'Suporte'},
        ],
        'PUT /api/v1/invoices/issuer': _issuer,
        'POST /api/v1/invoices/issuer/test': {
          'protocol': 'P1',
          'elapsedMs': 1200,
        },
        'PUT /api/v1/invoices/issuer/certificate': {
          ..._issuer,
          'certificateName': 'cert.pfx',
          'certificateExpiresOn': '2027-10-08',
        },
      });
      final repository = ApiIssuerRepository(dio);

      final setup = _ok(await repository.setup());
      expect(setup.kind, IssuerKind.municipal);
      expect(setup.certificateName, isNull);
      expect(_ok(await repository.serviceCodes()).single.code, '01.07');
      await repository.save(setup);
      expect(_sent(dio, 2), {
        'kind': 'MUNICIPAL',
        'city': 'Cidade Exemplo',
        'municipalRegistration': '123',
        'serviceCode': '01.07',
      });
      expect(
        _ok(await repository.emitTest(setup)).elapsed,
        const Duration(milliseconds: 1200),
      );
      final uploaded = _ok(
        await repository.uploadCertificate(
          _pfx,
          'senha',
          const CalendarDate(2027, 10, 8),
        ),
      );
      expect(uploaded.certificateExpiresOn, const CalendarDate(2027, 10, 8));
      expect(_sent(dio, 4)['expiresOn'], '2027-10-08');
      expect(_sent(dio, 4)['password'], 'senha');
    });

    test('no issuer saved yet reads as blank', () async {
      final repository = ApiIssuerRepository(
        _api({'GET /api/v1/invoices/issuer': null}),
      );

      expect(await repository.setup(), const Ok(IssuerSetup.blank));
    });
  });

  group('the other API repositories', () {
    test('transfers read the detail and download the statement', () async {
      final party = {
        'owner': 'PJ',
        'holder': 'Empresa Exemplo',
        'account': 'Conta 1',
        'accountId': 'acc1',
      };
      final repository = ApiTransfersRepository(
        _api({
          'GET /api/v1/transfers/t1': {
            'id': 't1',
            'kind': 'PROFIT_DISTRIBUTION',
            'amount': _money(100),
            'at': '2026-10-08T12:00:00.000Z',
            'rail': 'PIX',
            'from': party,
            'to': {...party, 'owner': 'PF'},
            'document': 'ata.pdf',
            'neutral': true,
          },
          'GET /api/v1/transfers/t1/document': StubResponse(
            200,
            Uint8List.fromList([3]),
          ),
        }),
      );

      final transfer = _ok(await repository.transfer('t1'));
      expect(transfer.to.owner, EntityKind.personal);
      expect(transfer.neutral, isTrue);
      final document = _ok(await repository.document('t1'));
      expect(document.name, 'transferencia-t1.pdf');
      expect(document.bytes, [3]);
      expect(
        await repository.document('t2'),
        const Err<LocalFile>(NotFoundFailure()),
      );
    });

    test('the export plans, lists, generates and downloads', () async {
      final dio = _api({
        'GET /api/v1/accountant-export/plan': {
          'from': '2026-09-01',
          'to': '2026-09-30',
          'items': [
            {
              'kind': 'TAX_GUIDES',
              'count': 3,
              'unit': 'DOCUMENTS',
              'files': 3,
              'bytes': 300,
              'selectedByDefault': true,
            },
          ],
        },
        'GET /api/v1/accountant-export/history': [_record],
        'POST /api/v1/accountant-export': _record,
        'GET /api/v1/accountant-export/e1/download': StubResponse(
          200,
          Uint8List.fromList([1]),
        ),
      });
      final repository = ApiAccountantExportRepository(dio);

      final plan = _ok(await repository.plan(ExportPeriod.lastQuarter));
      expect(plan.items.single.kind, ExportItemKind.taxGuides);
      expect(plan.items.single.count, '3');
      expect(adapterOf(dio).requests.first.queryParameters, {
        'period': 'LAST_QUARTER',
      });
      final record = _ok(await repository.history()).single;
      expect(record.to, isNull);
      await repository.generate(ExportPeriod.lastMonth, {
        ExportItemKind.invoices,
      });
      expect(_sent(dio, 2), {
        'period': 'LAST_MONTH',
        'items': ['INVOICES'],
      });
      expect(
        _ok(await repository.archive(record)).name,
        'contador-2026-09.zip',
      );
    });

    test('payroll reads the sheet and saves a month', () async {
      final dio = _api({
        'GET /api/v1/payroll': _sheet,
        'PUT /api/v1/payroll/2026-10': _sheet,
        'PUT /api/v1/payroll/annex': {..._sheet, 'declaredAnnex': 'III'},
      });
      final repository = ApiPayrollRepository(dio);

      final sheet = _ok(await repository.sheet());
      expect(sheet.current.proLabore, const Money(150000));
      await repository.save(
        sheet.current.copyWith(salaries: const Money(20000)),
      );
      expect(_sent(dio, 1), {
        'proLaboreCents': 150000,
        'salariesCents': 20000,
        'fgtsCents': 0,
      });
      expect(sheet.declaredAnnex, isNull);
      final declared = _ok(await repository.declareAnnex(SimplesAnnex.iii));
      expect(declared.declaredAnnex, SimplesAnnex.iii);
      expect(_sent(dio, 2), {'annex': 'III'});
      await repository.declareAnnex(SimplesAnnex.v);
      expect(_sent(dio, 3), {'annex': 'V'});
      await repository.declareAnnex(null);
      expect(_sent(dio, 4), {'annex': null});
    });

    test('the kill switch reads, pauses and resumes', () async {
      final repository = ApiAutomationRepository(
        _api({
          'GET /api/v1/automation': {'pausedSince': null},
          'POST /api/v1/automation/pause': {
            'pausedSince': '2026-10-08T12:00:00.000Z',
          },
          'POST /api/v1/automation/resume': {'pausedSince': null},
        }),
      );

      expect(_ok(await repository.status()).paused, isFalse);
      expect(_ok(await repository.pause()).paused, isTrue);
      expect(_ok(await repository.resume()), const AutomationStatus());
    });

    test('open finance looks up an item and imports accounts', () async {
      final dio = _api({
        'POST /api/v1/open-finance/lookup': {
          'status': 'FOUND',
          'institution': 'Banco Exemplo',
          'consentUntil': null,
          'accounts': [
            {'id': 'a1', 'name': 'Conta', 'balance': _money(-10)},
          ],
        },
        'POST /api/v1/open-finance/connections': {
          'connectionId': 'c1',
          'imported': 1,
        },
        'POST /api/v1/open-finance/connections/c1/sync': {
          'accounts': 1,
          'transactions': 12,
          'settledBills': 0,
          'syncedAt': '2026-10-08T15:00:00.000Z',
        },
      });
      final repository = ApiOpenFinanceRepository(dio);

      final lookup = _ok(await repository.lookup(' ABC ')) as ItemFound;
      expect(lookup.consentUntil, isNull);
      expect(_sent(dio, 0), {'itemId': 'abc'});
      expect(
        await repository.import('abc', {'a1'}, EntityKind.company),
        const Ok(1),
      );
      expect(_sent(dio, 1), {
        'itemId': 'abc',
        'entity': 'PJ',
        'accountIds': ['a1'],
      });
      expect(await repository.sync('c1', days: 90), const Ok(12));
      expect(adapterOf(dio).requests.last.queryParameters, {'days': 90});
      expect(itemLookupFromJson({'status': 'NOT_FOUND'}), const ItemNotFound());
      expect(
        itemLookupFromJson({'status': 'ALREADY_CONNECTED', 'owner': 'PF'}),
        const ItemAlreadyConnected(EntityKind.personal),
      );
      expect(
        () => itemLookupFromJson({'status': 'LOST'}),
        throwsFormatException,
      );
    });

    test('card import reads the latest draft and makes the bill', () async {
      final dio = _api({
        'GET /api/v1/card-statements/latest': _statement,
        'POST /api/v1/card-statements/s1/bill': {
          'billId': 'b9',
          'foreign': _money(1000, 'USD'),
          'subtotal': _money(5421),
          'iof': _money(190),
          'total': _money(5611),
        },
      });
      final repository = ApiCardImportRepository(dio);

      final statement = _ok(await repository.statement());
      expect(statement.lines.single.amount.currency, 'USD');
      expect(await repository.createBill(statement, {'l1'}), const Ok('b9'));
      expect(_sent(dio, 1), {
        'lineIds': ['l1'],
      });

      final read = ApiCardImportRepository(
        _api({'POST /api/v1/card-statements': _statement}),
      );
      final pdf = LocalFile(name: 'fatura.pdf', bytes: Uint8List(4));
      expect(_ok(await read.upload(pdf, EntityKind.company)).id, statement.id);

      final none = ApiCardImportRepository(
        _api({'GET /api/v1/card-statements/latest': null}),
      );
      expect(
        await none.statement(),
        const Err<CardStatement>(NotFoundFailure()),
      );
      expect(
        await ApiCardImportRepository(_api({})).statement(),
        const Err<CardStatement>(NotFoundFailure()),
      );
    });
  });

  test('the api backend wires every HTTP repository', () {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(backend: Backend.api, apiBaseUrl: 'https://x.test'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(homeRepositoryProvider), isA<ApiHomeRepository>());
    expect(container.read(railsRepositoryProvider), isA<ApiRailsRepository>());
    expect(
      container.read(captureRepositoryProvider),
      isA<ApiCaptureRepository>(),
    );
    expect(
      container.read(receiptsRepositoryProvider),
      isA<ApiReceiptsRepository>(),
    );
    expect(
      container.read(issuerRepositoryProvider),
      isA<ApiIssuerRepository>(),
    );
    expect(
      container.read(transfersRepositoryProvider),
      isA<ApiTransfersRepository>(),
    );
    expect(
      container.read(accountantExportRepositoryProvider),
      isA<ApiAccountantExportRepository>(),
    );
    expect(
      container.read(payrollRepositoryProvider),
      isA<ApiPayrollRepository>(),
    );
    expect(
      container.read(automationRepositoryProvider),
      isA<ApiAutomationRepository>(),
    );
    expect(
      container.read(openFinanceRepositoryProvider),
      isA<ApiOpenFinanceRepository>(),
    );
    expect(
      container.read(cardImportRepositoryProvider),
      isA<ApiCardImportRepository>(),
    );
  });
}
