import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/bills/data/api_bills_repository.dart';
import 'package:cashdeck/features/bills/data/bill_dtos.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/bills_repository.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';

void main() {
  group('billFromJson', () {
    test('maps every field', () {
      final bill = billFromJson(
        billJson(
          attempts: [
            {
              'id': 'attempt-1',
              'stepIndex': 0,
              'mode': 'AUTOMATIC',
              'rail': 'ASAAS',
              'amount': {'cents': 12345, 'currency': 'BRL'},
              'at': '2026-10-08T15:00:00Z',
              'outcome': 'FAILED',
              'reason': 'Sem saldo',
              'externalId': null,
            },
          ],
        ),
      );

      expect(
        bill,
        testBill(
          plan: const [LadderStep.automatic, LadderStep.assisted],
          attempts: [
            testAttempt(
              LadderStep.automatic,
              AttemptOutcome.failed,
              rail: 'ASAAS',
              reason: 'Sem saldo',
            ),
          ],
        ),
      );
    });

    test('a missing attempts list is empty', () {
      expect(billFromJson(billJson()).attempts, isEmpty);
      final bolepix = billFromJson({
        ...billJson(
          attempts: [
            {
              'id': 'a',
              'stepIndex': 0,
              'mode': 'AUTOMATIC',
              'rail': 'ASAAS',
              'method': 'PIX',
              'outcome': 'FAILED',
              'at': '2026-10-08T10:00:00.000Z',
            },
            {
              'id': 'b',
              'stepIndex': 0,
              'mode': 'AUTOMATIC',
              'rail': 'ASAAS',
              'method': 'BOLETO',
              'outcome': 'SUBMITTED',
              'at': '2026-10-08T10:01:00.000Z',
            },
          ],
        ),
        'pixCode': '000201abc',
      });
      expect(bolepix.isBolepix, isTrue);
      expect(bolepix.markedPaid(testNow).pixCode, '000201abc');
      expect(bolepix.attempts.map((attempt) => attempt.method), [
        PaymentMethod.pix,
        PaymentMethod.boleto,
      ]);
      expect(billFromJson(billJson()).isBolepix, isFalse);
      expect(
        () => billFromJson(
          billJson(
            attempts: [
              {
                'mode': 'AUTOMATIC',
                'rail': 'ASAAS',
                'method': 'TED',
                'outcome': 'FAILED',
                'at': '2026-10-08T10:00:00.000Z',
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('a bill without a plan yet has no ladder steps', () {
      expect(billFromJson(billJson(plan: null)).plan, isEmpty);
      expect(
        () => billFromJson(billJson(plan: 'AUTOMATIC')),
        throwsFormatException,
      );
    });

    test('a bill without a payee reads as blank', () {
      expect(billFromJson({...billJson(), 'payee': null}).payee, '');
    });

    test('folds the server statuses into the app ones', () {
      const expected = {
        'OPEN': BillStatus.pending,
        'NEEDS_CONFIRMATION': BillStatus.needsConfirmation,
        'PROCESSING': BillStatus.scheduled,
        'AWAITING_BANK_APPROVAL': BillStatus.awaitingApproval,
        'ASSISTED': BillStatus.pending,
        'PAID': BillStatus.paid,
        'CANCELLED': BillStatus.cancelled,
      };
      for (final entry in expected.entries) {
        expect(billFromJson(billJson(status: entry.key)).status, entry.value);
      }
    });

    test('maps every attempt outcome', () {
      const expected = {
        'PAID': AttemptOutcome.succeeded,
        'SUBMITTED': AttemptOutcome.waiting,
        'PENDING_APPROVAL': AttemptOutcome.waiting,
        'IN_FLIGHT': AttemptOutcome.waiting,
        'ASSISTED': AttemptOutcome.waiting,
        'FAILED': AttemptOutcome.failed,
      };
      for (final entry in expected.entries) {
        final attempt = attemptFromJson({
          'mode': 'ASSISTED',
          'rail': 'ASSISTED',
          'at': '2026-10-08T15:00:00Z',
          'outcome': entry.key,
        });
        expect(attempt.outcome, entry.value);
      }
    });

    test('an unknown enum value is a format error', () {
      expect(
        () => billFromJson(billJson(status: 'LOST')),
        throwsFormatException,
      );
    });

    test('reads money in cents', () {
      expect(
        readMoney({
          'amount': {'cents': 100, 'currency': 'USD'},
        }, 'amount'),
        const Money(100, currency: 'USD'),
      );
    });
  });

  group('ApiBillsRepository', () {
    final entities = {
      'data': [
        {'id': 'personal', 'kind': 'PF', 'name': 'Pessoal'},
      ],
    };

    test('walks the statuses that need the user first', () async {
      final dio = stubDio((options) {
        if (options.path == '/api/v1/entities') {
          return StubResponse(200, entities);
        }
        final query = options.queryParameters;
        return switch ((query['status'], query['cursor'])) {
          ('NEEDS_CONFIRMATION', null) => StubResponse(200, {
            'data': [billJson(id: 'a', status: 'NEEDS_CONFIRMATION')],
            'nextCursor': '1',
          }),
          ('NEEDS_CONFIRMATION', '1') => StubResponse(200, {
            'data': [billJson(id: 'b', status: 'NEEDS_CONFIRMATION')],
            'nextCursor': null,
          }),
          _ => const StubResponse(200, {
            'data': <Object?>[],
            'nextCursor': null,
          }),
        };
      });

      final result = await ApiBillsRepository(dio)
          .list(owner: EntityKind.personal);
      final page = (result as Ok<BillPage>).value;

      expect(page.bills.map((bill) => bill.id), ['a', 'b']);
      expect(page.nextCursor, isNull);
      final requests = adapterOf(dio).requests.skip(1).toList();
      expect(requests.map((request) => request.queryParameters['status']), [
        'NEEDS_CONFIRMATION',
        'NEEDS_CONFIRMATION',
        ...ApiBillsRepository.statusOrder.skip(1),
      ]);
      expect(requests.first.queryParameters['entityId'], 'personal');
      expect(requests.first.queryParameters['limit'], 50);
      expect(requests[1].queryParameters['cursor'], '1');
      expect(requests[1].queryParameters['limit'], 49);
    });

    test('stops at a full page and resumes from its cursor', () async {
      final dio = stubDio(
        (options) => StubResponse(200, {
          'data': [billJson(id: 'x-${options.queryParameters['status']}')],
          'nextCursor': options.queryParameters['status'] == 'OPEN'
              ? 'open-2'
              : null,
        }),
      );
      final repository = ApiBillsRepository(dio, pageSize: 1);

      final first = (await repository.list() as Ok<BillPage>).value;
      expect(first.bills.single.id, 'x-NEEDS_CONFIRMATION');
      expect(first.nextCursor, '1');
      expect(adapterOf(dio).requests.single.queryParameters, {
        'status': 'NEEDS_CONFIRMATION',
        'limit': 1,
      });

      final open = (await repository.list(cursor: '3') as Ok<BillPage>).value;
      expect(open.nextCursor, '3:open-2');
      final last = (await repository.list(cursor: '6') as Ok<BillPage>).value;
      expect(last.nextCursor, isNull);
      expect(
        await repository.list(cursor: '9'),
        const Err<BillPage>(UnexpectedFailure()),
      );
      expect(
        await repository.list(cursor: 'x:1'),
        const Err<BillPage>(UnexpectedFailure()),
      );
    });

    test('reads why a payment waits, when the server says', () {
      JsonMap waiting(String? reason) => {
        ...billJson(status: 'NEEDS_CONFIRMATION'),
        'confirmationReason': reason,
      };

      expect(
        billFromJson(waiting('ABOVE_THRESHOLD')).confirmationReason,
        ConfirmationReason.aboveThreshold,
      );
      expect(billFromJson(waiting('SOMETHING_NEW')).confirmationReason, isNull);
      expect(billFromJson(billJson()).confirmationReason, isNull);
    });

    test('gets one bill by id', () async {
      final dio = stubDio((_) => StubResponse(200, {'data': billJson()}));

      final result = await ApiBillsRepository(dio).get('bill 1');

      expect((result as Ok<Bill>).value.id, 'bill-1');
      expect(adapterOf(dio).requests.single.path, '/api/v1/bills/bill%201');
    });

    test('marks paid and pays with the confirmation flag', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {
          'data': {
            ...billJson(status: 'PAID'),
            'paidAt': '2026-10-08T15:00:00Z',
            'paidBy': 'USER',
          },
        }),
      );
      final repository = ApiBillsRepository(dio);

      final paid = (await repository.markPaid('bill-1') as Ok<Bill>).value;
      await repository.pay('bill-1', confirmed: false);
      await repository.pay('bill-1', confirmed: true);

      expect(paid.paidBy, PaidBy.user);
      expect(paid.paidAt, DateTime.utc(2026, 10, 8, 15));
      final requests = adapterOf(dio).requests;
      expect(requests.map((request) => request.path), [
        '/api/v1/bills/bill-1/mark-paid',
        '/api/v1/bills/bill-1/pay',
        '/api/v1/bills/bill-1/pay',
      ]);
      expect(requests[1].data, {'confirmed': false});
      expect(requests[2].data, {'confirmed': true});
    });

    test('turns auto debit on and reads it back', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {
          'data': {...billJson(), 'autoDebit': true},
        }),
      );

      final bill = (await ApiBillsRepository(
        dio,
      ).setAutoDebit('bill-1', enabled: true) as Ok<Bill>).value;

      expect(bill.autoDebit, isTrue);
      expect(bill.debitsItself, isTrue);
      final request = adapterOf(dio).requests.single;
      expect(request.method, 'PUT');
      expect(request.path, '/api/v1/bills/bill-1/auto-debit');
      expect(request.data, {'enabled': true});
      expect(billFromJson(billJson()).autoDebit, isFalse);
    });

    test('maps a 404 and a malformed body', () async {
      final missing = stubDio((_) => const StubResponse(404));
      final malformed = stubDio((_) => const StubResponse(200, {'data': 1}));

      expect(
        await ApiBillsRepository(missing).get('x'),
        const Err<Bill>(NotFoundFailure()),
      );
      expect(
        await ApiBillsRepository(malformed).list(),
        const Err<BillPage>(UnexpectedFailure()),
      );
    });
  });

  group('FakeBillsRepository', () {
    final repository = FakeBillsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );

    test('covers both entities and every ladder state', () async {
      final bills = (await repository.list() as Ok<BillPage>).value.bills;

      expect(
        bills.map((bill) => bill.owner).toSet(),
        EntityKind.values.toSet(),
      );
      expect(
        bills.map((bill) => bill.status).toSet(),
        containsAll([
          BillStatus.scheduled,
          BillStatus.pending,
          BillStatus.paid,
          BillStatus.awaitingApproval,
        ]),
      );
      expect(bills.any((bill) => bill.isOverdue(testToday)), isTrue);
    });

    test('pages by owner, open bills first', () async {
      final paged = FakeBillsRepository(
        FixedClock(testNow),
        latency: Duration.zero,
        pageSize: 2,
      );

      final first =
          (await paged.list(owner: EntityKind.company) as Ok<BillPage>).value;
      final rest = (await paged.list(
        owner: EntityKind.company,
        cursor: '2',
      ) as Ok<BillPage>).value;

      expect(first.nextCursor, '2');
      expect(first.bills.every((bill) => !bill.isSettled), isTrue);
      expect(rest.nextCursor, isNull);
      expect(
        [...first.bills, ...rest.bills].map((bill) => bill.owner).toSet(),
        {EntityKind.company},
      );
    });

    test('a mark or a confirmation sticks for the session', () async {
      final local = FakeBillsRepository(FixedClock(testNow));

      final paid = (await local.markPaid('bill-rent') as Ok<Bill>).value;
      final waiting =
          (await local.pay('bill-gym', confirmed: false) as Ok<Bill>).value;
      final confirmed =
          (await local.pay('bill-gym', confirmed: true) as Ok<Bill>).value;
      final again = (await local.get('bill-rent') as Ok<Bill>).value;

      expect(paid.status, BillStatus.paid);
      expect(paid.paidBy, PaidBy.user);
      expect(waiting.status, BillStatus.needsConfirmation);
      expect(waiting.confirmationReason, ConfirmationReason.newPayee);
      expect(confirmed.status, BillStatus.scheduled);
      expect(again, paid);
      expect(
        await local.markPaid('missing'),
        const Err<Bill>(NotFoundFailure()),
      );
      expect(
        await local.pay('missing', confirmed: true),
        const Err<Bill>(NotFoundFailure()),
      );
    });

    test('auto debit sticks for the session and survives a mark', () async {
      final local = FakeBillsRepository(FixedClock(testNow));

      final debited = (await local.setAutoDebit(
        'bill-gym',
        enabled: true,
      ) as Ok<Bill>).value;
      final paid = (await local.markPaid('bill-gym') as Ok<Bill>).value;

      expect(debited.autoDebit, isTrue);
      expect(paid.autoDebit, isTrue);
      expect(paid.debitsItself, isFalse);
      expect(
        await local.setAutoDebit('missing', enabled: true),
        const Err<Bill>(NotFoundFailure()),
      );
    });

    test('gets a bill by id or answers not found', () async {
      expect(await repository.get('bill-das'), isA<Ok<Bill>>());
      expect(
        await repository.get('missing'),
        const Err<Bill>(NotFoundFailure()),
      );
    });
  });
}
