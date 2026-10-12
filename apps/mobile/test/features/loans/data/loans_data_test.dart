import 'dart:convert';
import 'dart:typed_data';

import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/files/local_file.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/loans/data/api_loans_repository.dart';
import 'package:cashdeck/features/loans/data/fake_loans_repository.dart';
import 'package:cashdeck/features/loans/data/loan_dtos.dart';
import 'package:cashdeck/features/loans/loans_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/builders.dart';
import '../../../support/stub_http_adapter.dart';
import '../loan_builders.dart';

T _ok<T>(Result<T> result) => (result as Ok<T>).value;

final _pdf = LocalFile(name: 'extrato.pdf', bytes: Uint8List.fromList([1, 2]));

void main() {
  group('dtos', () {
    test('read a loan with its schedule summed up', () {
      final loan = loanFromJson(loanJson());
      expect(loan.effectiveRate, 11.9);
      expect(loan.cet, 12);
      expect(loan.propertyValue, const Money(30_000_000));
      expect(loan.next, testInstallment);
      expect(loan.upcoming, [testInstallment]);
      expect(loan.remaining.count, 405);
      expect(loan.paid.lateFees, const Money(9_300));
      expect(loan.lastDueOn, const CalendarDate(2060, 6, 17));

      final paidOff = loanFromJson(loanJson(next: null, property: null));
      expect(paidOff.next, isNull);
      expect(paidOff.propertyValue, isNull);
    });

    test('a rate that is not a number fails the read', () {
      expect(
        () => loanFromJson({...loanJson(), 'effectiveRate': '11.9'}),
        throwsFormatException,
      );
    });

    test('read a prepayment', () {
      final prepayment = prepaymentFromJson({
        'amount': moneyJson(1_000_000),
        'interestSaved': moneyJson(3_700_000),
        'feesSaved': moneyJson(90_000),
        'monthsCut': 15,
        'lastDueOn': '2059-03-17',
        'balanceAfter': moneyJson(23_600_000),
      });
      expect(prepayment, testPrepayment);
    });
  });

  group('api', () {
    test('lists, imports, simulates and deletes', () async {
      final dio = stubDio(
        (options) => switch ((options.method, options.path)) {
          ('GET', '/api/v1/loans') => StubResponse(200, {
            'data': {
              'items': [loanJson()],
            },
          }),
          ('POST', '/api/v1/loans/import') => StubResponse(201, {
            'data': loanJson(id: 'loan-2'),
          }),
          ('GET', '/api/v1/loans/loan-1/prepayment') => StubResponse(200, {
            'data': {
              'amount': moneyJson(1_000_000),
              'interestSaved': moneyJson(3_700_000),
              'feesSaved': moneyJson(90_000),
              'monthsCut': 15,
              'lastDueOn': '2059-03-17',
              'balanceAfter': moneyJson(23_600_000),
            },
          }),
          ('DELETE', '/api/v1/loans/loan-1') => const StubResponse(200, {
            'data': {'id': 'loan-1'},
          }),
          _ => const StubResponse(404),
        },
      );
      final repository = ApiLoansRepository(dio);

      expect(_ok(await repository.list()).single.id, 'loan-1');
      expect(_ok(await repository.importStatement(_pdf)).id, 'loan-2');
      expect(
        _ok(await repository.prepayment('loan-1', const Money(1_000_000))),
        testPrepayment,
      );
      expect(await repository.delete('loan-1'), isA<Ok<void>>());

      final requests = adapterOf(dio).requests;
      final upload = requests[1].data as Map<String, dynamic>;
      expect(upload['entity'], 'PF');
      expect(upload['mimeType'], 'application/pdf');
      expect(base64Decode(upload['base64'] as String), [1, 2]);
      expect(requests[2].queryParameters, {'amount': 1_000_000});
    });

    test(
      'a statement it cannot read comes back as a validation failure',
      () async {
        final dio = stubDio(
          (_) => const StubResponse(422, {
            'error': {'code': 'VALIDATION', 'message': 'Not a loan statement.'},
          }),
        );
        final result = await ApiLoansRepository(dio).importStatement(_pdf);
        expect((result as Err).failure, isA<ValidationFailure>());
      },
    );
  });

  group('fake', () {
    FakeLoansRepository fake() =>
        FakeLoansRepository(FixedClock(testNow), latency: Duration.zero);

    test('seeds a loan, imports another and refuses a non PDF', () async {
      final repository = fake();
      final seeded = _ok(await repository.list()).single;
      expect(seeded.paidCount, 12);
      expect(seeded.paidLate, isTrue);

      final imported = _ok(await repository.importStatement(_pdf));
      expect(_ok(await repository.list()).map((loan) => loan.id), [
        imported.id,
        seeded.id,
      ]);

      final image = LocalFile(name: 'foto.jpg', bytes: Uint8List(1));
      expect(
        (await repository.importStatement(image) as Err).failure,
        isA<ValidationFailure>(),
      );
    });

    test('simulates a prepayment and deletes', () async {
      final repository = fake();
      final loan = _ok(await repository.list()).single;
      final prepayment = _ok(
        await repository.prepayment(loan.id, const Money(150_000)),
      );
      expect(prepayment.monthsCut, 3);
      expect(prepayment.balanceAfter, loan.balance - const Money(150_000));
      expect(prepayment.lastDueOn, loan.lastDueOn.addDays(-90));

      expect(
        (await repository.prepayment('missing', const Money(1)) as Err).failure,
        const NotFoundFailure(),
      );
      expect(await repository.delete(loan.id), isA<Ok<void>>());
      expect(_ok(await repository.list()), isEmpty);
      expect(
        (await repository.delete(loan.id) as Err).failure,
        const NotFoundFailure(),
      );
    });
  });

  test('the backend picks the repository', () {
    for (final (backend, type) in [
      (Backend.fake, FakeLoansRepository),
      (Backend.api, ApiLoansRepository),
    ]) {
      final container = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(
            AppConfig(backend: backend, apiBaseUrl: 'https://api.test'),
          ),
          clockProvider.overrideWithValue(FixedClock(testNow)),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(loansRepositoryProvider).runtimeType, type);
      expect(container.read(listLoansProvider), isNotNull);
      expect(container.read(importLoanStatementProvider), isNotNull);
      expect(container.read(simulatePrepaymentProvider), isNotNull);
      expect(container.read(deleteLoanProvider), isNotNull);
    }
  });
}
