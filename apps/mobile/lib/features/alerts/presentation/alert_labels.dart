import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

String alertKindLabel(AppLocalizations l10n, AlertKind kind) => switch (kind) {
  AlertKind.billCaptured => l10n.alertKindBillCaptured,
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
