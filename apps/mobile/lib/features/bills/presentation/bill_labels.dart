import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/payment_ladder.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What a bill shows as its status. Overdue wins over the stored status, and
/// a bill on step 3 reads as the assisted path, never as a failure.
(String, MoneyTone) billStatusOf(
  AppLocalizations l10n,
  Bill bill,
  CalendarDate today,
) {
  if (bill.debitsItself) return (l10n.billAutoDebit, MoneyTone.scheduled);
  if (bill.isOverdue(today)) {
    return (l10n.billStatusOverdue, MoneyTone.overdue);
  }
  if (!bill.isSettled && currentStepOf(bill) == LadderStep.assisted) {
    return (l10n.billStatusAssisted, MoneyTone.assisted);
  }
  return switch (bill.status) {
    BillStatus.pending => (l10n.billStatusPending, MoneyTone.pending),
    BillStatus.needsConfirmation => (
      l10n.billStatusNeedsConfirmation,
      MoneyTone.pending,
    ),
    BillStatus.scheduled => (l10n.billStatusScheduled, MoneyTone.scheduled),
    BillStatus.awaitingApproval => (
      l10n.billStatusAwaitingApproval,
      MoneyTone.awaitingApproval,
    ),
    BillStatus.paid => (l10n.billStatusPaid, MoneyTone.paid),
    BillStatus.failed => (l10n.billStatusFailed, MoneyTone.failed),
    BillStatus.cancelled => (l10n.billStatusCancelled, MoneyTone.neutral),
  };
}

/// The shorter, action-first wording Início uses for the same status.
(String, MoneyTone) billHomeStatusOf(
  AppLocalizations l10n,
  Bill bill,
  CalendarDate today,
) {
  if (bill.debitsItself) return (l10n.billAutoDebit, MoneyTone.scheduled);
  if (bill.isOverdue(today)) return (l10n.billHomeOverdue, MoneyTone.overdue);
  if (bill.status == BillStatus.scheduled) {
    return (l10n.billHomeAutomatic(bill.dueDate.dayMonth), MoneyTone.scheduled);
  }
  return billStatusOf(l10n, bill, today);
}

/// Where the bill is on the ladder, as the line under a bill card reads.
String billLadderHint(AppLocalizations l10n, Bill bill) {
  if (bill.status == BillStatus.paid) {
    return bill.paidBy == PaidBy.user
        ? l10n.billPaidByYou
        : l10n.billPaidAutomatically;
  }
  if (bill.debitsItself) return l10n.billAutoDebitHint;
  final step = currentStepOf(bill);
  if (step == null) return '';
  final number = LadderStep.values.indexOf(step) + 1;
  if (step == LadderStep.assisted) return l10n.billHintAssisted(number);
  final rail = bill.attempts.where((a) => a.step == step).lastOrNull?.rail;
  if (rail == null) {
    return l10n.billHintStep(number, ladderStepTitle(l10n, step));
  }
  return l10n.billHintStep(number, rail);
}

String billDueLabel(AppLocalizations l10n, Bill bill, CalendarDate today) {
  final date = bill.dueDate.dayMonth;
  final paidAt = bill.paidAt;
  if (bill.status == BillStatus.paid && paidAt != null) {
    return l10n.billPaidOn(
      CalendarDate.brazilToday(paidAt).dayMonth,
      brazilTime(paidAt),
    );
  }
  if (bill.isOverdue(today)) return l10n.billOverdueSince(date);
  final days = today.daysUntil(bill.dueDate);
  return switch (days) {
    0 => l10n.billDueToday,
    1 => l10n.billDueTomorrow(date),
    _ => l10n.billDueInDays(date, days),
  };
}

IconData billIconOf(Bill bill) {
  final payee = bill.payee.toLowerCase();
  if (bill.isTax) return Symbols.account_balance_rounded;
  const keywords = {
    'energia': Symbols.bolt_rounded,
    'internet': Symbols.wifi_rounded,
    'aluguel': Symbols.home_rounded,
    'condom': Symbols.apartment_rounded,
    'água': Symbols.water_drop_rounded,
    'cowork': Symbols.work_rounded,
    'academia': Symbols.fitness_center_rounded,
  };
  for (final MapEntry(:key, :value) in keywords.entries) {
    if (payee.contains(key)) return value;
  }
  return Symbols.receipt_long_rounded;
}

String billKindLabel(AppLocalizations l10n, BillKind kind) => switch (kind) {
  BillKind.boleto => l10n.billKindBoleto,
  BillKind.pixKey => l10n.billKindPixKey,
  BillKind.pixQr => l10n.billKindPixQr,
  BillKind.taxBarcode => l10n.billKindTaxBarcode,
  BillKind.darfNoBarcode => l10n.billKindDarfNoBarcode,
};

/// What the detail line calls a bill: a boleto that also carries a Pix BR
/// Code reads as one.
String billKindLabelOf(AppLocalizations l10n, Bill bill) =>
    bill.isBolepix ? l10n.billKindBolepix : billKindLabel(l10n, bill.kind);

/// Who the bill pays, or what it is when the capture found no payee.
String billPayeeOf(AppLocalizations l10n, Bill bill) =>
    bill.payee.trim().isEmpty ? billKindLabelOf(l10n, bill) : bill.payee;

String paymentMethodLabel(AppLocalizations l10n, PaymentMethod method) =>
    switch (method) {
      PaymentMethod.pix => l10n.paymentMethodPix,
      PaymentMethod.boleto => l10n.paymentMethodBoleto,
    };

/// The ladder's failure codes read as a sentence; a rail's own message
/// passes through as the server wrote it.
String failureReasonLabel(AppLocalizations l10n, String reason) =>
    switch (reason) {
      'NOT_CONFIGURED' => l10n.reasonNotConfigured,
      'DAILY_CAP_EXCEEDED' => l10n.reasonDailyCap,
      'RAIL_UNAVAILABLE' => l10n.reasonRailUnavailable,
      'CONFIRMATION_DECLINED' => l10n.reasonConfirmationDeclined,
      _ => reason,
    };

String billSourceLabel(AppLocalizations l10n, BillSource source) =>
    switch (source) {
      BillSource.email => l10n.billSourceEmail,
      BillSource.share => l10n.billSourceShare,
      BillSource.camera => l10n.billSourceCamera,
      BillSource.chat => l10n.billSourceChat,
      BillSource.dda => l10n.billSourceDda,
      BillSource.manual => l10n.billSourceManual,
    };

String ladderStepTitle(AppLocalizations l10n, LadderStep step) =>
    switch (step) {
      LadderStep.automatic => l10n.ladderStepAutomatic,
      LadderStep.bankApproval => l10n.ladderStepBankApproval,
      LadderStep.assisted => l10n.ladderStepAssisted,
    };

String ladderStepHint(AppLocalizations l10n, LadderStep step) => switch (step) {
  LadderStep.automatic => l10n.ladderStepAutomaticHint,
  LadderStep.bankApproval => l10n.ladderStepBankApprovalHint,
  LadderStep.assisted => l10n.ladderStepAssistedHint,
};

String entityKindLabel(AppLocalizations l10n, EntityKind kind) =>
    switch (kind) {
      EntityKind.personal => l10n.entityPersonal,
      EntityKind.company => l10n.entityCompany,
    };

/// Why the confirmation sheet asks; a server that does not say gets the
/// generic safety line.
String confirmationReasonLabel(
  AppLocalizations l10n,
  ConfirmationReason? reason,
) => switch (reason) {
  ConfirmationReason.newPayee => l10n.confirmReasonNewPayee,
  ConfirmationReason.aboveThreshold => l10n.confirmReasonAboveThreshold,
  ConfirmationReason.amountDeviation => l10n.confirmReasonAmountDeviation,
  ConfirmationReason.capExceeded => l10n.confirmReasonCap,
  null => l10n.confirmReasonGeneric,
};
