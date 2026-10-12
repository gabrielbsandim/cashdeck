import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/home/domain/invoice_draft_edit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const before = InvoiceDraftDetail(
    id: 'draft',
    customer: 'Cliente Exemplo',
    description: 'Consultoria',
    amount: Money(5000),
    issueOn: CalendarDate(2026, 10, 10),
  );

  InvoiceDraftEdit editOf({
    String customer = 'Cliente Exemplo',
    String description = 'Consultoria',
    Money amount = const Money(5000),
    CalendarDate issueOn = const CalendarDate(2026, 10, 10),
  }) => InvoiceDraftEdit.between(
    before,
    customer: customer,
    description: description,
    amount: amount,
    issueOn: issueOn,
  );

  test('an untouched form is an empty edit', () {
    final edit = editOf(customer: ' Cliente Exemplo ');

    expect(edit.isEmpty, isTrue);
    expect(edit.problem, isNull);
    expect(edit.applyTo(before), before);
  });

  test('only the changed fields travel, trimmed', () {
    final edit = editOf(
      customer: ' Outro Cliente ',
      description: 'Suporte',
      amount: const Money(7000),
      issueOn: const CalendarDate(2026, 10, 15),
    );

    expect(
      edit,
      const InvoiceDraftEdit(
        customer: 'Outro Cliente',
        description: 'Suporte',
        amount: Money(7000),
        issueOn: CalendarDate(2026, 10, 15),
      ),
    );
    expect(edit.isEmpty, isFalse);
    expect(
      edit.applyTo(before),
      const InvoiceDraftDetail(
        id: 'draft',
        customer: 'Outro Cliente',
        description: 'Suporte',
        amount: Money(7000),
        issueOn: CalendarDate(2026, 10, 15),
      ),
    );
  });

  test('a blank name or text, or no amount, is caught before sending', () {
    expect(editOf(customer: '  ').problem, InvoiceDraftProblem.customerMissing);
    expect(
      editOf(description: '').problem,
      InvoiceDraftProblem.descriptionMissing,
    );
    expect(
      editOf(amount: const Money(0)).problem,
      InvoiceDraftProblem.amountMissing,
    );
    expect(editOf(amount: const Money(1)).problem, isNull);
  });
}
