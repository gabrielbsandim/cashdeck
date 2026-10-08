import {
  type Bill,
  type BillStatus,
  billStatusFor,
  currentStep,
  idempotencyKey,
  isAtAssistedStep,
  isSettled,
  jumpToAssisted,
  type LocalDate,
  markBillPaid,
  moveDown,
  type PaymentAttempt,
  type PaymentPlan,
  type PaymentStep,
  toLocalDate,
  transitionBill,
} from '@cashdeck/domain'
import { NotFoundError, ProviderNotConfiguredError } from '@/errors/errors'
import {
  type AssistedInstructions,
  type RailResult,
} from '@/ports/payment-rail'
import {
  type AuditLog,
  type BillRepository,
  type IdempotencyStore,
  type PayeeDirectory,
  type PaymentSettings,
} from '@/ports/repositories'
import { type Clock, type IdGenerator } from '@/ports/system'
import {
  type BuildPaymentPlanDeps,
  makeBuildPaymentPlan,
} from '@/use-cases/build-payment-plan'

export type RunPaymentLadderDeps = BuildPaymentPlanDeps & {
  bills: BillRepository
  payees: PayeeDirectory
  idempotency: IdempotencyStore
  audit: AuditLog
  clock: Clock
  ids: IdGenerator
}

export type LadderRun = {
  bill: Bill
  plan: PaymentPlan
  attempts: PaymentAttempt[]
  instructions: AssistedInstructions | null
}

const WAITING: readonly BillStatus[] = [
  'PROCESSING',
  'AWAITING_BANK_APPROVAL',
  'ASSISTED',
]

export function assistedInstructions(bill: Bill): AssistedInstructions {
  return {
    kind: bill.kind,
    copyCode: bill.code,
    amountCents: bill.amount.cents,
    dueDate: bill.dueDate,
  }
}

export function payeeKey(bill: Bill): string {
  return bill.payee ?? bill.code ?? bill.id
}

function failureReason(error: unknown): string {
  if (error instanceof ProviderNotConfiguredError) {
    return 'NOT_CONFIGURED'
  }
  if (error instanceof Error) {
    return error.message
  }
  return 'UNKNOWN_ERROR'
}

const failed = (reason: string): RailResult => ({ outcome: 'FAILED', reason })

export function makeRunPaymentLadder(deps: RunPaymentLadderDeps) {
  const buildPlan = makeBuildPaymentPlan(deps)

  async function exceedsCap(
    tenantId: string,
    bill: Bill,
    step: PaymentStep,
    settings: PaymentSettings,
    today: LocalDate,
  ): Promise<boolean> {
    const cap = settings.dailyCapCents[step.rail]
    if (cap === undefined) {
      return false
    }
    const committed = await deps.payments.committedCents(
      tenantId,
      step.rail,
      today,
    )
    return committed + bill.amount.cents > cap
  }

  // Assisted is the terminal step and is resolved here, never by a rail, so it
  // cannot fail. A stored rail result is replayed so a retry never pays twice.
  async function attemptStep(
    tenantId: string,
    bill: Bill,
    plan: PaymentPlan,
    settings: PaymentSettings,
    today: LocalDate,
  ): Promise<RailResult> {
    const step = currentStep(plan)
    if (step.mode === 'ASSISTED') {
      return { outcome: 'ASSISTED', instructions: assistedInstructions(bill) }
    }
    const rail = deps.rails.get(step.rail)
    if (!rail) {
      return failed('RAIL_UNAVAILABLE')
    }
    if (await exceedsCap(tenantId, bill, step, settings, today)) {
      return failed('DAILY_CAP_EXCEEDED')
    }
    const key = idempotencyKey(bill.id, plan.currentStep)
    const previous = await deps.idempotency.find<RailResult>(tenantId, key)
    if (previous) {
      return previous
    }
    try {
      const result = await rail.pay({
        bill,
        mode: step.mode,
        idempotencyKey: key,
      })
      await deps.idempotency.save(tenantId, key, 'payment', result)
      return result
    } catch (error) {
      return failed(failureReason(error))
    }
  }

  async function record(
    tenantId: string,
    bill: Bill,
    plan: PaymentPlan,
    result: RailResult,
  ): Promise<PaymentAttempt> {
    const step = currentStep(plan)
    const attempt: PaymentAttempt = {
      id: deps.ids.next(),
      billId: bill.id,
      stepIndex: plan.currentStep,
      rail: step.rail,
      mode: step.mode,
      amount: bill.amount,
      outcome: result.outcome,
      reason: result.reason ?? null,
      externalId: result.externalId ?? null,
      idempotencyKey: idempotencyKey(bill.id, plan.currentStep),
      at: deps.clock.now(),
    }
    await deps.payments.addAttempt(tenantId, attempt)
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'SYSTEM',
      action: 'payment.attempt',
      subjectId: bill.id,
      rail: step.rail,
      result: result.outcome,
      details: {
        stepIndex: attempt.stepIndex,
        reason: attempt.reason,
        idempotencyKey: attempt.idempotencyKey,
      },
      at: attempt.at,
    })
    return attempt
  }

  async function needsConfirmation(
    tenantId: string,
    bill: Bill,
    plan: PaymentPlan,
    settings: PaymentSettings,
  ): Promise<boolean> {
    if (isAtAssistedStep(plan)) {
      return false
    }
    const known = await deps.payees.isKnown(
      tenantId,
      bill.entityId,
      payeeKey(bill),
    )
    const threshold = settings.confirmAboveCents
    return !known || (threshold !== null && bill.amount.cents > threshold)
  }

  async function askForConfirmation(
    tenantId: string,
    bill: Bill,
    plan: PaymentPlan,
  ): Promise<LadderRun> {
    const pending = transitionBill(bill, 'NEEDS_CONFIRMATION')
    await deps.bills.save(pending)
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'SYSTEM',
      action: 'payment.confirmation_requested',
      subjectId: bill.id,
      rail: currentStep(plan).rail,
      result: 'NEEDS_CONFIRMATION',
      details: {},
      at: deps.clock.now(),
    })
    return { bill: pending, plan, attempts: [], instructions: null }
  }

  return async function runPaymentLadder(
    tenantId: string,
    billId: string,
    options: { confirmed?: boolean } = {},
  ): Promise<LadderRun> {
    const bill = await deps.bills.findById(tenantId, billId)
    if (!bill) {
      throw new NotFoundError('Bill')
    }
    const stored = await deps.payments.findPlan(tenantId, billId)
    const plan = stored ?? (await buildPlan(tenantId, bill))
    if (isSettled(bill) || WAITING.includes(bill.status)) {
      return { bill, plan, attempts: [], instructions: null }
    }
    const settings = await deps.settings.get(tenantId, bill.entityId)
    let current = settings.killSwitch ? jumpToAssisted(plan) : plan
    const confirmed = options.confirmed === true
    if (
      !confirmed &&
      (await needsConfirmation(tenantId, bill, current, settings))
    ) {
      return askForConfirmation(tenantId, bill, current)
    }
    const ready = transitionBill(bill, 'OPEN')
    const today = toLocalDate(deps.clock.now())
    const attempts: PaymentAttempt[] = []
    let result = await attemptStep(tenantId, ready, current, settings, today)
    attempts.push(await record(tenantId, ready, current, result))
    while (result.outcome === 'FAILED') {
      current = moveDown(current)
      result = await attemptStep(tenantId, ready, current, settings, today)
      attempts.push(await record(tenantId, ready, current, result))
    }
    const finished =
      result.outcome === 'PAID'
        ? markBillPaid(ready, 'RAIL', deps.clock.now())
        : transitionBill(ready, billStatusFor(result.outcome))
    await deps.bills.save(finished)
    await deps.payments.savePlan(tenantId, current)
    if (confirmed) {
      await deps.payees.remember(tenantId, bill.entityId, payeeKey(bill))
    }
    return {
      bill: finished,
      plan: current,
      attempts,
      instructions: result.instructions ?? null,
    }
  }
}
