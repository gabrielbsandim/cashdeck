import 'package:cashdeck/core/network/json_reader.dart';
import 'package:cashdeck/features/loans/domain/loan.dart';

double _readNumber(JsonMap json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Expected a number at "$key"', json);
}

LoanInstallment installmentFromJson(JsonMap json) => LoanInstallment(
  number: readInt(json, 'number'),
  dueOn: readDate(json, 'dueOn'),
  total: readMoney(json, 'total'),
  principal: readMoney(json, 'principal'),
  interest: readMoney(json, 'interest'),
  fees: readMoney(json, 'fees'),
);

Loan loanFromJson(JsonMap json) {
  final remaining = readMap(json, 'remaining');
  final paid = readMap(json, 'paid');
  final next = readOptionalMap(json, 'next');
  final property = readOptionalMap(json, 'propertyValue');
  return Loan(
    id: readString(json, 'id'),
    name: readString(json, 'name'),
    lender: readString(json, 'lender'),
    system: readString(json, 'system'),
    indexer: readString(json, 'indexer'),
    effectiveRate: _readNumber(json, 'effectiveRate'),
    cet: _readNumber(json, 'cet'),
    principal: readMoney(json, 'principal'),
    propertyValue: property == null ? null : moneyFromJson(property),
    termMonths: readInt(json, 'termMonths'),
    paidCount: readInt(json, 'paidCount'),
    balance: readMoney(json, 'balance'),
    balanceOn: readDate(json, 'balanceOn'),
    lastDueOn: readDate(json, 'lastDueOn'),
    next: next == null ? null : installmentFromJson(next),
    upcoming: readMapList(json, 'upcoming').map(installmentFromJson).toList(),
    remaining: LoanRemaining(
      count: readInt(remaining, 'count'),
      total: readMoney(remaining, 'total'),
      interest: readMoney(remaining, 'interest'),
      principal: readMoney(remaining, 'principal'),
      fees: readMoney(remaining, 'fees'),
    ),
    paid: LoanPaid(
      total: readMoney(paid, 'total'),
      interest: readMoney(paid, 'interest'),
      principal: readMoney(paid, 'principal'),
      lateFees: readMoney(paid, 'lateFees'),
    ),
  );
}

Prepayment prepaymentFromJson(JsonMap json) => Prepayment(
  amount: readMoney(json, 'amount'),
  interestSaved: readMoney(json, 'interestSaved'),
  feesSaved: readMoney(json, 'feesSaved'),
  monthsCut: readInt(json, 'monthsCut'),
  lastDueOn: readDate(json, 'lastDueOn'),
  balanceAfter: readMoney(json, 'balanceAfter'),
);
