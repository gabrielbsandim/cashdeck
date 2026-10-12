import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:cashdeck/features/insights/presentation/insights_labels.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

String alertKindLabel(AppLocalizations l10n, AlertKind kind) => switch (kind) {
  AlertKind.billCaptured => l10n.alertKindBillCaptured,
  AlertKind.billNeedsAmount => l10n.alertKindBillNeedsAmount,
  AlertKind.billDueSoon => l10n.alertKindBillDueSoon,
  AlertKind.paymentNeedsConfirmation => l10n.alertKindPaymentNeedsConfirmation,
  AlertKind.paymentPaid => l10n.alertKindPaymentPaid,
  AlertKind.paymentMovedDown => l10n.alertKindPaymentMovedDown,
  AlertKind.paymentAssisted => l10n.alertKindPaymentAssisted,
  AlertKind.approvalPending => l10n.alertKindApprovalPending,
  AlertKind.lowBalance => l10n.alertKindLowBalance,
  AlertKind.invoiceIssued => l10n.alertKindInvoiceIssued,
  AlertKind.invoiceFailed => l10n.alertKindInvoiceFailed,
  AlertKind.cardBillClosed => l10n.alertKindCardBillClosed,
  AlertKind.jobFailed => l10n.alertKindJobFailed,
  AlertKind.unusualPurchase => l10n.alertKindUnusualPurchase,
  AlertKind.subscriptionChanged => l10n.alertKindSubscriptionChanged,
  AlertKind.cardBillAboveAverage => l10n.alertKindCardBillAboveAverage,
  AlertKind.bankSyncStale => l10n.alertKindBankSyncStale,
  AlertKind.invoiceNotIssued => l10n.alertKindInvoiceNotIssued,
  AlertKind.budgetNearLimit => l10n.alertKindBudgetNearLimit,
  AlertKind.budgetLimitReached => l10n.alertKindBudgetLimitReached,
  AlertKind.monthlyRecap => l10n.alertKindMonthlyRecap,
  AlertKind.other => l10n.alertKindOther,
};

IconData alertKindIcon(AlertKind kind) => switch (kind) {
  AlertKind.billCaptured => Symbols.inbox_rounded,
  AlertKind.billNeedsAmount => Symbols.edit_note_rounded,
  AlertKind.billDueSoon => Symbols.event_upcoming_rounded,
  AlertKind.paymentNeedsConfirmation => Symbols.help_rounded,
  AlertKind.paymentPaid => Symbols.task_alt_rounded,
  AlertKind.paymentMovedDown => Symbols.alt_route_rounded,
  AlertKind.paymentAssisted => Symbols.qr_code_rounded,
  AlertKind.approvalPending => Symbols.account_balance_rounded,
  AlertKind.lowBalance => Symbols.savings_rounded,
  AlertKind.invoiceIssued => Symbols.receipt_rounded,
  AlertKind.invoiceFailed => Symbols.error_rounded,
  AlertKind.cardBillClosed => Symbols.credit_card_rounded,
  AlertKind.jobFailed => Symbols.running_with_errors_rounded,
  AlertKind.unusualPurchase => Symbols.troubleshoot_rounded,
  AlertKind.subscriptionChanged => Symbols.autorenew_rounded,
  AlertKind.cardBillAboveAverage => Symbols.trending_up_rounded,
  AlertKind.bankSyncStale => Symbols.sync_problem_rounded,
  AlertKind.invoiceNotIssued => Symbols.pending_actions_rounded,
  AlertKind.budgetNearLimit => Symbols.donut_small_rounded,
  AlertKind.budgetLimitReached => Symbols.donut_large_rounded,
  AlertKind.monthlyRecap => Symbols.auto_stories_rounded,
  AlertKind.other => Symbols.notifications_rounded,
};

/// The warning tone of the kinds that report something went wrong on the
/// server side; null keeps the row neutral.
MoneyTone? alertKindTone(AlertKind kind) => switch (kind) {
  AlertKind.jobFailed => MoneyTone.overdue,
  _ => null,
};

typedef AlertText = ({String title, String body});

/// The alert in the app language, built from its type and data; an alert
/// missing a field keeps the text the server wrote.
AlertText alertText(AppLocalizations l10n, AppAlert alert) {
  final stored = (title: alert.title, body: alert.body);
  final builder = _builders[alert.kind];
  if (builder == null) return stored;
  try {
    return builder(l10n, _AlertData(alert.data));
  } on _MissingField {
    return stored;
  }
}

final class _MissingField implements Exception;

extension type const _AlertData(Map<String, String> fields) {
  String operator [](String key) => fields[key] ?? (throw _MissingField());

  String get due => '${this['payee']} · ${this['amount']}';
}

typedef _Builder = AlertText Function(AppLocalizations l10n, _AlertData d);

final Map<AlertKind, _Builder> _builders = {
  AlertKind.billCaptured: (l10n, d) => (
    title: l10n.alertTextBillCapturedTitle,
    body: l10n.alertTextBillCapturedBody(d.due, d['dueDate']),
  ),
  AlertKind.billNeedsAmount: (l10n, d) => (
    title: l10n.alertTextBillNeedsAmountTitle,
    body: l10n.alertTextBillNeedsAmountBody(d['payee'], _source(l10n, d)),
  ),
  AlertKind.billDueSoon: (l10n, d) => (
    title: l10n.alertTextBillDueSoonTitle,
    body: l10n.alertTextBillDueSoonBody(d.due),
  ),
  AlertKind.paymentNeedsConfirmation: (l10n, d) => (
    title: l10n.alertTextNeedsConfirmationTitle,
    body: l10n.alertTextNeedsConfirmationBody(d.due),
  ),
  AlertKind.paymentPaid: (l10n, d) =>
      (title: l10n.alertTextPaidTitle, body: l10n.alertTextPaidBody(d.due)),
  AlertKind.paymentMovedDown: (l10n, d) => (
    title: l10n.alertTextMovedDownTitle,
    body: l10n.alertTextMovedDownBody(d.due, d['rail']),
  ),
  AlertKind.paymentAssisted: (l10n, d) => (
    title: l10n.alertTextAssistedTitle,
    body: l10n.alertTextAssistedBody(d.due, _hint(l10n, d['method'])),
  ),
  AlertKind.approvalPending: (l10n, d) => (
    title: l10n.alertTextApprovalTitle,
    body: l10n.alertTextApprovalBody(d.due),
  ),
  AlertKind.lowBalance: (l10n, d) => (
    title: l10n.alertTextLowBalanceTitle,
    body: l10n.alertTextLowBalanceBody(d['shortfall'], d['dueDate']),
  ),
  AlertKind.invoiceIssued: (l10n, d) => (
    title: l10n.alertTextInvoiceIssuedTitle,
    body: l10n.alertTextInvoiceIssuedBody(
      _invoice(l10n, d),
      d['client'],
      d['amount'],
    ),
  ),
  AlertKind.invoiceFailed: (l10n, d) => (
    title: l10n.alertTextInvoiceFailedTitle,
    body: l10n.alertTextInvoiceFailedBody(
      _invoice(l10n, d),
      d['client'],
      d['amount'],
    ),
  ),
  AlertKind.cardBillClosed: (l10n, d) => (
    title: l10n.alertTextCardClosedTitle,
    body: l10n.alertTextCardClosedBody(d['card'], d['closing'], d['dueDate']),
  ),
  AlertKind.jobFailed: _jobFailed,
  AlertKind.unusualPurchase: (l10n, d) => (
    title: l10n.alertTextUnusualTitle,
    body: l10n.alertTextUnusualBody(
      d['merchant'],
      d['amount'],
      d['day'],
      d['times'],
      d['usual'],
    ),
  ),
  AlertKind.subscriptionChanged: _subscriptionChanged,
  AlertKind.cardBillAboveAverage: (l10n, d) => (
    title: l10n.alertTextBillAboveTitle,
    body: l10n.alertTextBillAboveBody(
      d['card'],
      d['amount'],
      d['percent'],
      d['average'],
      d['dueDate'],
    ),
  ),
  AlertKind.bankSyncStale: (l10n, d) => (
    title: l10n.alertTextSyncStaleTitle,
    body: switch (d.fields['hours'] ?? '') {
      '' => l10n.alertTextSyncStaleBody(d['institution']),
      final hours => l10n.alertTextSyncStaleHoursBody(d['institution'], hours),
    },
  ),
  AlertKind.invoiceNotIssued: (l10n, d) => (
    title: l10n.alertTextInvoiceMissingTitle,
    body: l10n.alertTextInvoiceMissingBody(d['client'], d['amount'], d['day']),
  ),
  AlertKind.budgetNearLimit: (l10n, d) => (
    title: l10n.alertTextBudgetNearTitle,
    body: l10n.alertTextBudgetNearBody(
      _category(l10n, d),
      d['spent'],
      d['limit'],
      d['percent'],
    ),
  ),
  AlertKind.budgetLimitReached: (l10n, d) => (
    title: l10n.alertTextBudgetReachedTitle,
    body: l10n.alertTextBudgetReachedBody(
      _category(l10n, d),
      d['spent'],
      d['limit'],
    ),
  ),
  AlertKind.monthlyRecap: (l10n, d) => (
    title: d.fields['entity'] == 'PJ'
        ? l10n.alertTextRecapCompanyTitle(_month(l10n, d))
        : l10n.alertTextRecapTitle(_month(l10n, d)),
    body: l10n.alertTextRecapBody(d['income'], d['expenses']),
  ),
};

/// A run that threw names its error; one that finished with items left
/// behind counts them.
AlertText _jobFailed(AppLocalizations l10n, _AlertData d) {
  final failures = d.fields['failures'];
  if (failures == null) {
    return (
      title: l10n.alertTextJobFailedTitle,
      body: l10n.alertTextJobFailedBody(d['job'], d['error']),
    );
  }
  final count = int.tryParse(failures) ?? (throw _MissingField());
  return (
    title: l10n.alertTextJobPartialTitle,
    body: l10n.alertTextJobPartialBody(d['job'], count),
  );
}

/// The month the alert is about, as sentences name it.
String _month(AppLocalizations l10n, _AlertData d) {
  try {
    return monthName(l10n, YearMonth.parse(d['month']));
  } on FormatException {
    throw _MissingField();
  }
}

AlertText _subscriptionChanged(AppLocalizations l10n, _AlertData d) {
  if (d['change'] == 'DUPLICATE') {
    return (
      title: l10n.alertTextSubscriptionTwiceTitle,
      body: l10n.alertTextSubscriptionTwiceBody(
        d['name'],
        d['count'],
        d['amount'],
      ),
    );
  }
  return (
    title: l10n.alertTextSubscriptionUpTitle,
    body: l10n.alertTextSubscriptionUpBody(
      d['name'],
      d['previous'],
      d['amount'],
      d['percent'],
    ),
  );
}

/// A built-in category in the app language, from the key the alert carries.
String _category(AppLocalizations l10n, _AlertData d) {
  final key = d.fields['categoryKey'];
  return categoryName(
    l10n,
    Category(
      id: d.fields['categoryId'] ?? '',
      key: key == null || key.isEmpty ? null : key,
      name: d['category'],
    ),
  );
}

String _hint(AppLocalizations l10n, String method) => switch (method) {
  'PIX' => l10n.alertTextHintPix,
  'BARCODE' => l10n.alertTextHintBarcode,
  _ => l10n.alertTextHintNone,
};

// Older alerts carry only the pt-BR name the server picked.
String _source(AppLocalizations l10n, _AlertData d) {
  final kind = d.fields['sourceKind'];
  final named = d.fields['source'];
  if (kind == 'GMAIL' || named == 'e-mail') return l10n.alertTextSourceEmail;
  return kind ?? d['source'];
}

final _numbered = RegExp(r'^Nota (.+)$');

String _invoice(AppLocalizations l10n, _AlertData d) {
  final number =
      d.fields['number'] ??
      _numbered.firstMatch(d.fields['invoice'] ?? '')?.group(1) ??
      '';
  if (number.isEmpty) return l10n.alertTextInvoice;
  return l10n.alertTextInvoiceNumber(number);
}
