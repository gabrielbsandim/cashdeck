import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/bills/data/api_bills_repository.dart';
import 'package:cashdeck/features/bills/data/bill_dtos.dart';
import 'package:cashdeck/features/bills/data/fake_bills_repository.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
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
        moneyFromJson({'cents': 100, 'currency': 'USD'}),
        const Money(100, currency: 'USD'),
      );
    });
  });

  group('ApiBillsRepository', () {
    test('lists bills from the data envelope', () async {
      final dio = stubDio(
        (_) => StubResponse(200, {
          'data': [billJson(id: 'a'), billJson(id: 'b')],
        }),
      );

      final result = await ApiBillsRepository(dio).list();

      expect((result as Ok<List<Bill>>).value.map((bill) => bill.id), [
        'a',
        'b',
      ]);
      expect(adapterOf(dio).requests.single.path, ApiBillsRepository.path);
    });

    test('gets one bill by id', () async {
      final dio = stubDio((_) => StubResponse(200, {'data': billJson()}));

      final result = await ApiBillsRepository(dio).get('bill 1');

      expect((result as Ok<Bill>).value.id, 'bill-1');
      expect(adapterOf(dio).requests.single.path, '/api/v1/bills/bill%201');
    });

    test('marks paid and confirms through their endpoints', () async {
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
      await repository.confirmPayment('bill-1');

      expect(paid.paidBy, PaidBy.user);
      expect(paid.paidAt, DateTime.utc(2026, 10, 8, 15));
      expect(adapterOf(dio).requests.map((request) => request.path), [
        '/api/v1/bills/bill-1/mark-paid',
        '/api/v1/bills/bill-1/pay',
      ]);
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
        const Err<List<Bill>>(UnexpectedFailure()),
      );
    });
  });

  group('FakeBillsRepository', () {
    final repository = FakeBillsRepository(
      FixedClock(testNow),
      latency: Duration.zero,
    );

    test('covers both entities and every ladder state', () async {
      final bills = (await repository.list() as Ok<List<Bill>>).value;

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

    test('a mark or a confirmation sticks for the session', () async {
      final local = FakeBillsRepository(FixedClock(testNow));

      final paid = (await local.markPaid('bill-rent') as Ok<Bill>).value;
      final confirmed =
          (await local.confirmPayment('bill-gym') as Ok<Bill>).value;
      final again = (await local.get('bill-rent') as Ok<Bill>).value;

      expect(paid.status, BillStatus.paid);
      expect(paid.paidBy, PaidBy.user);
      expect(confirmed.status, BillStatus.scheduled);
      expect(again, paid);
      expect(
        await local.markPaid('missing'),
        const Err<Bill>(NotFoundFailure()),
      );
      expect(
        await local.confirmPayment('missing'),
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
