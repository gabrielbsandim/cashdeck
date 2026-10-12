import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:equatable/equatable.dart';

/// The part of a draft invoice the editor shows, read from the server.
final class InvoiceDraftDetail extends Equatable {
  const new({
    required this.id,
    required this.customer,
    required this.description,
    required this.amount,
    required this.issueOn,
  });

  final String id;
  final String customer;
  final String description;
  final Money amount;
  final CalendarDate issueOn;

  @override
  List<Object?> get props => [id, customer, description, amount, issueOn];
}

enum InvoiceDraftProblem { customerMissing, descriptionMissing, amountMissing }

/// What the user changed in a draft; a null field stays as it was, so the
/// server only rewrites what was touched.
final class InvoiceDraftEdit extends Equatable {
  const new({this.customer, this.description, this.amount, this.issueOn});

  /// The form values against [before], blank text trimmed first.
  factory between(
    InvoiceDraftDetail before, {
    required String customer,
    required String description,
    required Money amount,
    required CalendarDate issueOn,
  }) {
    final name = customer.trim();
    final text = description.trim();
    return InvoiceDraftEdit(
      customer: name == before.customer ? null : name,
      description: text == before.description ? null : text,
      amount: amount == before.amount ? null : amount,
      issueOn: issueOn == before.issueOn ? null : issueOn,
    );
  }

  final String? customer;
  final String? description;
  final Money? amount;
  final CalendarDate? issueOn;

  bool get isEmpty =>
      customer == null &&
      description == null &&
      amount == null &&
      issueOn == null;

  /// The first thing the server would refuse, checked before sending.
  InvoiceDraftProblem? get problem => switch (this) {
    InvoiceDraftEdit(customer: '') => InvoiceDraftProblem.customerMissing,
    InvoiceDraftEdit(description: '') => InvoiceDraftProblem.descriptionMissing,
    InvoiceDraftEdit(:final amount?) when amount.cents <= 0 =>
      InvoiceDraftProblem.amountMissing,
    _ => null,
  };

  /// [before] with the changes applied, as the server keeps it.
  InvoiceDraftDetail applyTo(InvoiceDraftDetail before) => InvoiceDraftDetail(
    id: before.id,
    customer: customer ?? before.customer,
    description: description ?? before.description,
    amount: amount ?? before.amount,
    issueOn: issueOn ?? before.issueOn,
  );

  @override
  List<Object?> get props => [customer, description, amount, issueOn];
}
