import {
  jumpToAssisted,
  reopenAssisted,
  restartPlan,
  retryBlock,
} from '@cashdeck/domain'
import { NotFoundError, RetryRefusedError } from '@/errors/errors'
import { type Actor } from '@/ports/repositories'
import {
  type LadderRun,
  makeRunPaymentLadder,
  type RunPaymentLadderDeps,
} from '@/use-cases/run-payment-ladder'

type RunLadder = ReturnType<typeof makeRunPaymentLadder>

export function makeRetryPayment(
  deps: RunPaymentLadderDeps,
  runLadder: RunLadder = makeRunPaymentLadder(deps),
) {
  return async function retryPayment(
    tenantId: string,
    billId: string,
    options: { actor: Actor },
  ): Promise<LadderRun> {
    const bill = await deps.bills.findById(tenantId, billId)
    if (!bill) {
      throw new NotFoundError('Bill')
    }
    // Every path into ASSISTED stores the plan, so a bill without one never
    // went down the ladder.
    const plan = await deps.payments.findPlan(tenantId, billId)
    if (!plan) {
      throw new RetryRefusedError('NOT_ASSISTED')
    }
    const settings = await deps.settings.get(tenantId, bill.entityId)
    const blocked = retryBlock({
      bill,
      plan,
      attempts: await deps.payments.listAttempts(tenantId, billId),
      killSwitch: settings.killSwitch,
    })
    if (blocked) {
      throw new RetryRefusedError(blocked)
    }
    const restarted = restartPlan(plan)
    const claimed = await deps.idempotency.claim(
      tenantId,
      `${billId}:retry:r${restarted.round}`,
      'payment.retry',
      { actorId: options.actor.id },
    )
    if (!claimed) {
      throw new RetryRefusedError('NOT_ASSISTED')
    }
    try {
      // An open bill with the old plan would walk from the assisted step again.
      await deps.payments.savePlan(tenantId, restarted)
      await deps.bills.save(reopenAssisted(bill))
    } catch (error) {
      // The claimed round is spent; parking the plan on its assisted step lets
      // the next retry claim the round after it.
      await deps.payments.savePlan(tenantId, jumpToAssisted(restarted))
      throw error
    }
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: options.actor.kind,
      actorId: options.actor.id,
      requestId: options.actor.requestId,
      subjectId: billId,
      at: deps.clock.now(),
      action: 'payment.retry_requested',
      rail: null,
      result: 'OPEN',
      details: { round: restarted.round },
    })
    return runLadder(tenantId, billId, {
      confirmed: true,
      actor: options.actor,
    })
  }
}
