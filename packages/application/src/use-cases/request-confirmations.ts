import {
  addDays,
  type Bill,
  isAtAssistedStep,
  recipientKeys,
  toLocalDate,
  transitionBill,
} from '@cashdeck/domain'
import { type ConfirmationReason } from '@/dtos/bill'
import { type AlertEmitter } from '@/ports/alerts'
import { billAlert } from '@/use-cases/alert-events'
import { type AutoDebitCheck, loadAutoDebit } from '@/use-cases/auto-debit'
import { makeBuildPaymentPlan } from '@/use-cases/build-payment-plan'
import { makeConfirmationCheck } from '@/use-cases/payment-guards'
import { type RunPaymentLadderDeps } from '@/use-cases/run-payment-ladder'
import { allPages } from '@/use-cases/shared'

export const CONFIRM_AHEAD_DAYS = 3

export type RequestConfirmationsDeps = RunPaymentLadderDeps & {
  alerts: AlertEmitter
}

export type RequestConfirmationsResult = { requested: number }

// Asks days before the payment run, so a new payee or an odd amount is
// confirmed in time and the run pays without waiting on the user.
export function makeRequestConfirmations(deps: RequestConfirmationsDeps) {
  const buildPlan = makeBuildPaymentPlan(deps)
  const confirmationReasons = makeConfirmationCheck(deps)

  async function reasonsFor(
    tenantId: string,
    bill: Bill,
    isAutoDebit: AutoDebitCheck,
  ): Promise<ConfirmationReason[]> {
    const settings = await deps.settings.get(tenantId, bill.entityId)
    if (settings.killSwitch || isAutoDebit(bill)) {
      return []
    }
    const attempts = await deps.payments.listAttempts(tenantId, bill.id)
    if (attempts.length > 0) {
      return []
    }
    const plan =
      (await deps.payments.findPlan(tenantId, bill.id)) ??
      (await buildPlan(tenantId, bill))
    if (isAtAssistedStep(plan)) {
      return []
    }
    return confirmationReasons(tenantId, bill, settings)
  }

  async function request(
    bill: Bill,
    reasons: readonly ConfirmationReason[],
  ): Promise<void> {
    const pending = transitionBill(bill, 'NEEDS_CONFIRMATION')
    await deps.bills.save(pending)
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId: bill.tenantId,
      actor: 'SYSTEM',
      action: 'payment.confirmation_requested',
      subjectId: bill.id,
      rail: null,
      result: 'NEEDS_CONFIRMATION',
      details: { reasons, recipients: recipientKeys(bill), ahead: true },
      at: deps.clock.now(),
    })
    await deps.alerts.emit(billAlert('PAYMENT_NEEDS_CONFIRMATION', pending))
  }

  return async function requestConfirmations(
    tenantId: string,
  ): Promise<RequestConfirmationsResult> {
    const today = toLocalDate(deps.clock.now())
    const until = addDays(today, CONFIRM_AHEAD_DAYS)
    const open = await allPages(page =>
      deps.bills.list(tenantId, { status: 'OPEN' }, page),
    )
    const isAutoDebit = await loadAutoDebit(deps, tenantId)
    let requested = 0
    for (const bill of open) {
      if (bill.dueDate < today || bill.dueDate > until) {
        continue
      }
      const reasons = await reasonsFor(tenantId, bill, isAutoDebit)
      if (reasons.length === 0) {
        continue
      }
      await request(bill, reasons)
      requested += 1
    }
    return { requested }
  }
}
