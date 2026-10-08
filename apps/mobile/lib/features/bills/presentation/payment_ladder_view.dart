import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/money/cd_copy_field.dart';
import 'package:cashdeck/core/widgets/money/cd_payment_ladder.dart';
import 'package:cashdeck/features/bills/domain/bill.dart';
import 'package:cashdeck/features/bills/domain/payment_ladder.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What the user can do from a ladder step; the screen owns the effects.
final class LadderActions {
  const new({
    required this.onMarkPaid,
    required this.onReceipt,
    required this.onOpenBank,
    required this.onApproved,
    required this.onConfirm,
  });

  final VoidCallback onMarkPaid;
  final VoidCallback onReceipt;
  final VoidCallback onOpenBank;
  final VoidCallback onApproved;
  final VoidCallback onConfirm;
}

/// A bill's payment ladder: every step, what was tried, the visible
/// step-down after each failure and what happens next.
class PaymentLadderView extends StatelessWidget {
  const new({
    required this.bill,
    required this.today,
    required this.actions,
    super.key,
  });

  static Key stepKey(LadderStep step) => Key('ladder-${step.name}');
  static const markPaidKey = Key('ladder-mark-paid');
  static const receiptKey = Key('ladder-receipt');
  static const openBankKey = Key('ladder-open-bank');
  static const approvedKey = Key('ladder-approved');
  static const confirmKey = Key('ladder-confirm');
  static const copyKey = Key('ladder-copy');
  static const copyPixKey = Key('ladder-copy-pix');

  final Bill bill;
  final CalendarDate today;
  final LadderActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final statuses = ladderOf(bill);
    final current = currentStepOf(bill);
    final entity = entityKindLabel(l10n, bill.owner);
    final position = current == null
        ? l10n.ladderSettled
        : l10n.ladderPosition(LadderStep.values.indexOf(current) + 1, 3);
    final pastFailures = statuses
        .where((status) => status.state == LadderStepState.failed)
        .length;
    final collapse = current == LadderStep.assisted && pastFailures > 1;
    return CdPaymentLadder(
      title: l10n.ladderTitle,
      subtitle: '$entity · $position',
      steps: [
        for (final (index, status) in statuses.indexed)
          _step(l10n, status, index, statuses, collapse: collapse),
      ],
      nextAction: switch (current) {
        LadderStep.bankApproval => l10n.ladderNextApprove,
        _ => null,
      },
      footnote: current == LadderStep.assisted
          ? l10n.ladderAssistedFootnote(bill.dueDate.dayMonth)
          : null,
    );
  }

  CdLadderStep _step(
    AppLocalizations l10n,
    LadderStepStatus status,
    int index,
    List<LadderStepStatus> all, {
    required bool collapse,
  }) {
    final step = status.step;
    final base = (
      number: index + 1,
      title: ladderStepTitle(l10n, step),
      icon: switch (step) {
        LadderStep.automatic => Symbols.bolt_rounded,
        LadderStep.bankApproval => Symbols.approval_rounded,
        LadderStep.assisted => Symbols.verified_user_rounded,
      },
      tone: switch (step) {
        LadderStep.automatic => MoneyTone.scheduled,
        LadderStep.bankApproval => MoneyTone.awaitingApproval,
        LadderStep.assisted => MoneyTone.assisted,
      },
      key: stepKey(step),
    );
    final lines = [
      for (final attempt in status.attempts)
        CdLadderLine(_attemptLine(l10n, attempt), time: brazilTime(attempt.at)),
    ];
    return switch (status.state) {
      LadderStepState.unavailable => CdLadderStep(
        number: base.number,
        title: base.title,
        icon: base.icon,
        tone: base.tone,
        key: base.key,
        state: CdLadderState.skipped,
        body: l10n.ladderStateUnavailable,
      ),
      LadderStepState.done => CdLadderStep(
        number: base.number,
        title: base.title,
        icon: base.icon,
        tone: base.tone,
        key: base.key,
        state: CdLadderState.done,
        badge: CdStatusBadge(tone: MoneyTone.paid, label: l10n.ladderStateDone),
        lines: lines,
      ),
      LadderStepState.failed => CdLadderStep(
        number: base.number,
        title: base.title,
        icon: base.icon,
        tone: base.tone,
        key: base.key,
        state: CdLadderState.failed,
        badge: CdStatusBadge(
          tone: MoneyTone.failed,
          label: l10n.ladderStateFailed,
        ),
        lines: lines,
        stepDown: _stepDown(l10n, status, index, all),
        summary: collapse
            ? l10n.ladderCollapsed(
                lines.last.time ?? '',
                switch (status.attempts.last.reason) {
                  null => status.attempts.last.rail,
                  final reason => failureReasonLabel(l10n, reason),
                },
                status.attempts.length,
              )
            : null,
      ),
      LadderStepState.active => _active(l10n, status, base, lines),
      LadderStepState.upcoming || LadderStepState.skipped => CdLadderStep(
        number: base.number,
        title: base.title,
        icon: base.icon,
        tone: base.tone,
        key: base.key,
        state: CdLadderState.upcoming,
        trailingLabel: switch ((status.state, step)) {
          (LadderStepState.skipped, _) => l10n.ladderStateSkipped,
          (_, LadderStep.assisted) => l10n.ladderSafetyNet,
          _ => null,
        },
        body: ladderStepHint(l10n, step),
      ),
    };
  }

  String? _stepDown(
    AppLocalizations l10n,
    LadderStepStatus status,
    int index,
    List<LadderStepStatus> all,
  ) {
    final next = all
        .skip(index + 1)
        .where((s) => s.state != LadderStepState.unavailable)
        .firstOrNull;
    if (next == null || status.attempts.isEmpty) return null;
    final time = brazilTime(status.attempts.last.at);
    final target = LadderStep.values.indexOf(next.step) + 1;
    final skipped = LadderStep.values.indexOf(next.step) > index + 1;
    if (skipped) return l10n.ladderJumped(target, time);
    return l10n.ladderSteppedDown(target, time);
  }

  CdLadderStep _active(
    AppLocalizations l10n,
    LadderStepStatus status,
    ({int number, String title, IconData icon, MoneyTone tone, Key key}) base,
    List<CdLadderLine> lines,
  ) {
    final code = bill.paymentCode;
    final pix = bill.pixCode;
    return switch (status.step) {
      LadderStep.assisted => CdLadderStep(
        number: base.number,
        title: l10n.ladderReadyTitle,
        icon: base.icon,
        tone: base.tone,
        key: base.key,
        state: CdLadderState.ready,
        body: code == null
            ? l10n.ladderReadyPixKey(bill.dueDate.dayMonth)
            : l10n.ladderReadyBody(bill.dueDate.dayMonth),
        actions: [
          if (pix != null)
            CdCopyField(
              code: pix,
              label: l10n.pixCopyPasteLabel,
              compact: true,
              buttonKey: copyPixKey,
            ),
          if (code != null)
            CdCopyField(
              code: code,
              label: pix == null ? null : l10n.paymentCodeLabel,
              compact: true,
              buttonKey: copyKey,
            ),
          Row(
            children: [
              Expanded(
                child: CdButton.filled(
                  key: markPaidKey,
                  dense: true,
                  expand: true,
                  icon: Symbols.task_alt_rounded,
                  label: l10n.markPaidButton,
                  onPressed: actions.onMarkPaid,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CdButton.outlined(
                  key: receiptKey,
                  dense: true,
                  expand: true,
                  icon: Symbols.attach_file_rounded,
                  label: l10n.receiptButton,
                  onPressed: actions.onReceipt,
                ),
              ),
            ],
          ),
        ],
      ),
      LadderStep.bankApproval => CdLadderStep(
        number: base.number,
        title: base.title,
        icon: base.icon,
        tone: base.tone,
        key: base.key,
        state: CdLadderState.active,
        badge: CdStatusBadge(
          tone: MoneyTone.awaitingApproval,
          label: l10n.ladderWaitingForYou,
        ),
        lines: lines,
        body: l10n.ladderApprovalBody(
          status.attempts.lastOrNull?.rail ?? l10n.ladderStepBankApproval,
        ),
        actions: [
          CdButton.filled(
            key: openBankKey,
            dense: true,
            icon: Symbols.open_in_new_rounded,
            label: l10n.openBankButton,
            onPressed: actions.onOpenBank,
          ),
          CdButton.text(
            key: approvedKey,
            dense: true,
            label: l10n.alreadyApprovedButton,
            onPressed: actions.onApproved,
          ),
        ],
      ),
      LadderStep.automatic => CdLadderStep(
        number: base.number,
        title: base.title,
        icon: base.icon,
        tone: base.tone,
        key: base.key,
        state: CdLadderState.active,
        badge: bill.status == BillStatus.needsConfirmation
            ? CdStatusBadge(
                tone: MoneyTone.pending,
                label: l10n.billStatusNeedsConfirmation,
                icon: Symbols.touch_app_rounded,
              )
            : CdStatusBadge(
                tone: MoneyTone.scheduled,
                label: l10n.billStatusScheduled,
              ),
        lines: lines,
        body: bill.status == BillStatus.needsConfirmation
            ? l10n.ladderConfirmBody
            : l10n.ladderStepAutomaticHint,
        actions: [
          if (bill.status == BillStatus.needsConfirmation)
            CdButton.filled(
              key: confirmKey,
              dense: true,
              icon: Symbols.fingerprint_rounded,
              label: l10n.reviewAndConfirmButton,
              onPressed: actions.onConfirm,
            ),
        ],
      ),
    };
  }
}

/// The rail, with the method first when the server says which one it tried,
/// then the reason it stopped.
String _attemptLine(AppLocalizations l10n, PaymentAttempt attempt) {
  final method = attempt.method;
  final how = method == null
      ? attempt.rail
      : l10n.attemptVia(paymentMethodLabel(l10n, method), attempt.rail);
  final reason = attempt.reason;
  if (reason == null) return how;
  return '$how, ${failureReasonLabel(l10n, reason)}';
}
