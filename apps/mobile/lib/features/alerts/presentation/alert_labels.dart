import 'package:cashdeck/features/alerts/domain/app_alert.dart';
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
  AlertKind.other => Symbols.notifications_rounded,
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
};

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
