import {
  approvalExpired,
  type Bill,
  type BillStatus,
  billStatusFor,
  inFlightAttempt,
  jumpToAssisted,
  latestAttempts,
  markBillPaid,
  type PaymentAttempt,
  type RailId,
  transitionBill,
} from '@cashdeck/domain'
import { type Deps } from '@/use-cases/deps'
import {
  makeResolveInFlight,
  type ResolvedPayment,
} from '@/use-cases/payment-guards'
import { allPages } from '@/use-cases/shared'
import { assistedAlert, billAlert, emitAlert } from '@/use-cases/alert-events'

type ReconcileDeps = Pick<
  Deps,
  | 'bills'
  | 'payments'
  | 'railStatus'
  | 'idempotency'
  | 'settings'
  | 'audit'
  | 'clock'
  | 'ids'
> &
  Partial<Pick<Deps, 'alerts'>>

export type ReconcileResult = {
  checked: number
  paid: number
  failed: number
  expired: number
  failures: Array<{ billId: string; reason: string }>
}

type Outcome = 'PAID' | 'FAILED' | 'EXPIRED' | null

// A webhook names one payment by the provider's own id.
export type ReconcileTarget = { rail: RailId; reference: string }

// Stored ids carry a resource prefix (`pix:id`) or a pair (`payout/transaction`).
export function referenceMatches(externalId: string, reference: string) {
  return (
    externalId === reference || externalId.split(/[:/]/).includes(reference)
  )
}

const WAITING: readonly BillStatus[] = ['PROCESSING', 'AWAITING_BANK_APPROVAL']

// A lost answer gets this long to show up at the rail before the bill goes to
// assisted, so a slow rail is not mistaken for one that never received it.
export const IN_FLIGHT_GRACE_MS = 15 * 60 * 1000

export const APPROVAL_EXPIRED = 'APPROVAL_EXPIRED'
export const IN_FLIGHT_UNRESOLVED = 'IN_FLIGHT_UNRESOLVED'

const isOpenAttempt = (attempt: PaymentAttempt) =>
  (attempt.outcome === 'SUBMITTED' || attempt.outcome === 'PENDING_APPROVAL') &&
  attempt.externalId !== null

// Asks the rail that took each waiting payment for its final state. A payment
// the rail reports as failed goes to assisted, never to another rail.
export function makeReconcilePayments(deps: ReconcileDeps) {
  const resolveInFlight = makeResolveInFlight(deps)

  async function waitingBills(tenantId: string): Promise<Bill[]> {
    const bills: Bill[] = []
    for (const status of WAITING) {
      bills.push(
        ...(await allPages(page =>
          deps.bills.list(tenantId, { status }, page),
        )),
      )
    }
    return bills
  }

  async function record(
    tenantId: string,
    from: PaymentAttempt,
    result: ResolvedPayment,
    action: string,
  ): Promise<void> {
    const at = deps.clock.now()
    const externalId = result.externalId ?? from.externalId
    const reason = result.reason ?? null
    await deps.payments.addAttempt(tenantId, {
      ...from,
      id: deps.ids.next(),
      outcome: result.outcome,
      externalId,
      reason,
      at,
    })
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'SYSTEM',
      action,
      subjectId: from.billId,
      rail: from.rail,
      result: result.outcome,
      details: { externalId, reason, idempotencyKey: from.idempotencyKey },
      at,
    })
  }

  async function toAssisted(
    tenantId: string,
    bill: Bill,
    from: PaymentAttempt | undefined,
    reason: string,
    action: string,
  ): Promise<void> {
    if (from) {
      await record(tenantId, from, { outcome: 'FAILED', reason }, action)
    }
    const plan = await deps.payments.findPlan(tenantId, bill.id)
    if (plan) {
      await deps.payments.savePlan(tenantId, jumpToAssisted(plan))
    }
    await deps.bills.save(transitionBill(bill, 'ASSISTED'))
    await emitAlert(deps.alerts, assistedAlert(bill, reason))
  }

  async function apply(
    tenantId: string,
    bill: Bill,
    attempt: PaymentAttempt,
    status: ResolvedPayment,
  ): Promise<Outcome> {
    switch (status.outcome) {
      case 'PAID': {
        await record(tenantId, attempt, status, 'payment.reconciled')
        const paidAt = status.settledAt
          ? new Date(status.settledAt)
          : deps.clock.now()
        await deps.bills.save(markBillPaid(bill, 'RAIL', paidAt))
        await emitAlert(deps.alerts, billAlert('PAYMENT_PAID', bill))
        return 'PAID'
      }
      case 'FAILED':
        await toAssisted(
          tenantId,
          bill,
          attempt,
          status.reason ?? 'RAIL_FAILED',
          'payment.reconciled',
        )
        return 'FAILED'
      default:
        return null
    }
  }

  // A found payment that is still open is written down with its external id,
  // so the next pass polls it like any other submitted payment.
  async function adopt(
    tenantId: string,
    bill: Bill,
    pending: PaymentAttempt,
    found: ResolvedPayment,
  ): Promise<Outcome> {
    if (found.outcome === 'PAID' || found.outcome === 'FAILED') {
      return apply(tenantId, bill, pending, found)
    }
    await record(tenantId, pending, found, 'payment.reconciled')
    await deps.bills.save(transitionBill(bill, billStatusFor(found.outcome)))
    return null
  }

  async function settleInFlight(
    tenantId: string,
    bill: Bill,
    pending: PaymentAttempt,
  ): Promise<Outcome> {
    const found = await resolveInFlight(tenantId, bill.entityId, pending)
    if (found) {
      return adopt(tenantId, bill, pending, found)
    }
    const age = deps.clock.now().getTime() - pending.at.getTime()
    if (age < IN_FLIGHT_GRACE_MS) {
      return null
    }
    await toAssisted(
      tenantId,
      bill,
      pending,
      IN_FLIGHT_UNRESOLVED,
      'payment.in_flight_unresolved',
    )
    return 'EXPIRED'
  }

  // A batch nobody approved before the cutoff is moved to assisted so the bill
  // is still paid on time by hand.
  async function expireApproval(
    tenantId: string,
    bill: Bill,
    open: PaymentAttempt | undefined,
  ): Promise<Outcome> {
    const settings = await deps.settings.get(tenantId, bill.entityId)
    const expired =
      bill.status === 'AWAITING_BANK_APPROVAL' &&
      approvalExpired(bill.dueDate, settings.approvalCutoff, deps.clock.now())
    if (!expired) {
      return null
    }
    await toAssisted(
      tenantId,
      bill,
      open,
      APPROVAL_EXPIRED,
      'payment.approval_expired',
    )
    return 'EXPIRED'
  }

  async function readStatus(
    tenantId: string,
    bill: Bill,
    open: PaymentAttempt,
  ): Promise<ResolvedPayment | null> {
    const reader = deps.railStatus.get(open.rail)
    if (!reader) {
      return null
    }
    return reader.status(open.externalId as string, {
      tenantId,
      entityId: bill.entityId,
    })
  }

  async function reconcileBill(tenantId: string, bill: Bill): Promise<Outcome> {
    const attempts = await deps.payments.listAttempts(tenantId, bill.id)
    const pending = inFlightAttempt(attempts)
    if (pending) {
      return settleInFlight(tenantId, bill, pending)
    }
    const open = latestAttempts(attempts).filter(isOpenAttempt).at(-1)
    const status = open ? await readStatus(tenantId, bill, open) : null
    const settled =
      open && status ? await apply(tenantId, bill, open, status) : null
    return settled ?? expireApproval(tenantId, bill, open)
  }

  async function targeted(
    tenantId: string,
    bills: Bill[],
    target: ReconcileTarget,
  ): Promise<Bill[]> {
    const matching: Bill[] = []
    for (const bill of bills) {
      const attempts = await deps.payments.listAttempts(tenantId, bill.id)
      const open = latestAttempts(attempts).filter(isOpenAttempt).at(-1)
      const hit =
        open?.rail === target.rail &&
        referenceMatches(open.externalId as string, target.reference)
      matching.push(...(hit ? [bill] : []))
    }
    return matching
  }

  return async function reconcilePayments(
    tenantId: string,
    target?: ReconcileTarget,
  ): Promise<ReconcileResult> {
    const result: ReconcileResult = {
      checked: 0,
      paid: 0,
      failed: 0,
      expired: 0,
      failures: [],
    }
    const waiting = await waitingBills(tenantId)
    const bills = target ? await targeted(tenantId, waiting, target) : waiting
    for (const bill of bills) {
      result.checked += 1
      try {
        const outcome = await reconcileBill(tenantId, bill)
        result.paid += outcome === 'PAID' ? 1 : 0
        result.failed += outcome === 'FAILED' ? 1 : 0
        result.expired += outcome === 'EXPIRED' ? 1 : 0
      } catch (error) {
        result.failures.push({ billId: bill.id, reason: String(error) })
      }
    }
    return result
  }
}
