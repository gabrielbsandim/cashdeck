import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';

Map<String, Object?> moneyJson(int cents) => {
  'cents': cents,
  'currency': 'BRL',
};

Map<String, Object?> installmentJson(int number, String dueOn) => {
  'number': number,
  'dueOn': dueOn,
  'total': moneyJson(300_000),
  'principal': moneyJson(60_000),
  'interest': moneyJson(234_000),
  'fees': moneyJson(6_000),
};

Map<String, Object?> loanJson({
  String id = 'loan-1',
  Object? next = const {},
  Object? property = 30_000_000,
  int lateFees = 9_300,
}) => {
  'id': id,
  'entity': 'PF',
  'name': 'Banco Exemplo 1001',
  'lender': 'Banco Exemplo',
  'contract': '1001',
  'system': 'SAC',
  'indexer': 'TR',
  'effectiveRate': 11.9,
  'cet': 12,
  'principal': moneyJson(25_000_000),
  'propertyValue': property == null ? null : moneyJson(property as int),
  'signedOn': '2025-05-23',
  'termMonths': 420,
  'paidCount': 15,
  'balance': moneyJson(24_600_000),
  'balanceOn': '2026-10-09',
  'lastDueOn': '2060-06-17',
  'next': next == null ? null : installmentJson(16, '2026-10-17'),
  'upcoming': [installmentJson(16, '2026-10-17')],
  'remaining': {
    'count': 405,
    'total': moneyJson(75_000_000),
    'interest': moneyJson(47_000_000),
    'principal': moneyJson(24_600_000),
    'fees': moneyJson(3_400_000),
  },
  'paid': {
    'total': moneyJson(4_700_000),
    'interest': moneyJson(3_700_000),
    'principal': moneyJson(900_000),
    'lateFees': moneyJson(lateFees),
  },
  'importedAt': '2026-10-12T15:00:00.000Z',
};

const testInstallment = LoanInstallment(
  number: 16,
  dueOn: CalendarDate(2026, 10, 17),
  total: Money(300_000),
  principal: Money(60_000),
  interest: Money(234_000),
  fees: Money(6_000),
);

Loan loanWith({int paidCount = 15, int termMonths = 420, int lateFees = 0}) =>
    Loan(
      id: 'loan-1',
      name: 'Banco Exemplo 1001',
      lender: 'Banco Exemplo',
      system: 'SAC',
      indexer: 'TR',
      effectiveRate: 11.9,
      cet: 12,
      principal: const Money(25_000_000),
      termMonths: termMonths,
      paidCount: paidCount,
      balance: const Money(24_600_000),
      balanceOn: const CalendarDate(2026, 10, 9),
      lastDueOn: const CalendarDate(2060, 6, 17),
      next: testInstallment,
      upcoming: const [testInstallment],
      remaining: const LoanRemaining(
        count: 405,
        total: Money(75_000_000),
        interest: Money(47_000_000),
        principal: Money(24_600_000),
        fees: Money(3_400_000),
      ),
      paid: LoanPaid(
        total: const Money(4_700_000),
        interest: const Money(3_700_000),
        principal: const Money(900_000),
        lateFees: Money(lateFees),
      ),
    );

const testPrepayment = Prepayment(
  amount: Money(1_000_000),
  interestSaved: Money(3_700_000),
  feesSaved: Money(90_000),
  monthsCut: 15,
  lastDueOn: CalendarDate(2059, 3, 17),
  balanceAfter: Money(23_600_000),
);
