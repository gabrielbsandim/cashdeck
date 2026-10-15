import { type PaymentAttempt } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import {
  type WebhookDelivery,
  type WithdrawalCheck,
  type WithdrawalRefusal,
  type WithdrawalVerdict,
} from '@/ports/webhooks'
import { type Deps } from '@/use-cases/deps'

type Judgement = { verdict: WithdrawalVerdict; attempt: PaymentAttempt | null }

const refuse = (
  reason: WithdrawalRefusal,
  attempt: PaymentAttempt | null = null,
): Judgement => ({ verdict: { approved: false, reason }, attempt })

// Approves only what the ladder sent and still waits on, for that amount; the
// provider cancels anything refused, including operations made elsewhere.
export function makeValidateWithdrawal(
  deps: Pick<
    Deps,
    'webhooks' | 'payments' | 'bills' | 'settings' | 'audit' | 'clock' | 'ids'
  >,
) {
  async function judge(
    tenantId: string,
    check: WithdrawalCheck,
  ): Promise<Judgement> {
    if (!check.externalId) {
      return refuse('UNKNOWN_OPERATION')
    }
    const attempt = await deps.payments.findAttemptByExternalId(
      tenantId,
      check.rail,
      check.externalId,
    )
    if (!attempt) {
      return refuse('UNKNOWN_OPERATION')
    }
    if (attempt.outcome !== 'SUBMITTED') {
      return refuse('NOT_PENDING', attempt)
    }
    if (attempt.amount.cents !== check.amountCents) {
      return refuse('AMOUNT_MISMATCH', attempt)
    }
    const bill = await deps.bills.findById(tenantId, attempt.billId)
    if (!bill) {
      return refuse('UNKNOWN_OPERATION', attempt)
    }
    const settings = await deps.settings.get(tenantId, bill.entityId)
    if (settings.killSwitch) {
      return refuse('KILL_SWITCH', attempt)
    }
    return { verdict: { approved: true }, attempt }
  }

  return async function validateWithdrawal(
    tenantId: string,
    delivery: WebhookDelivery,
  ): Promise<WithdrawalVerdict> {
    const reader = deps.webhooks.get(delivery.provider)
    if (!reader?.readWithdrawal) {
      throw new NotFoundError('Withdrawal validation provider')
    }
    const check = await reader.readWithdrawal(tenantId, delivery)
    const { verdict, attempt } = await judge(tenantId, check)
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'SYSTEM',
      action: 'payment.withdrawal_check',
      subjectId: attempt?.billId ?? check.externalId ?? check.operation,
      rail: check.rail,
      result: verdict.approved ? 'APPROVED' : 'REFUSED',
      details: {
        operation: check.operation,
        externalId: check.externalId,
        amountCents: check.amountCents,
        reason: verdict.approved ? null : verdict.reason,
      },
      at: deps.clock.now(),
    })
    return verdict
  }
}
