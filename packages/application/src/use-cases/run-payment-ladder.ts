import {
  type Bill,
  type BillStatus,
  billStatusFor,
  currentStep,
  type FinancialEntity,
  hasCommittedAttempt,
  idempotencyKey,
  inFlightAttempt,
  isAtAssistedStep,
  jumpToAssisted,
  type LocalDate,
  markBillPaid,
  moveDown,
  type PaymentAttempt,
  type PaymentPlan,
  type PaymentStep,
  type RailId,
  recipientKeys,
  toLocalDate,
  transitionBill,
} from '@cashdeck/domain'
import { NotFoundError, ProviderNotConfiguredError } from '@/errors/errors'
import {
  type AssistedInstructions,
  type PaymentRail,
  type RailResult,
} from '@/ports/payment-rail'
import { type RailStatusReader } from '@/ports/rail-status'
import { type DocumentStore } from '@/ports/records'
import { type ReserveFunder } from '@/ports/reserve-funder'
import {
  type Actor,
  type AuditEvent,
  type AuditLog,
  type BillRepository,
  type FundingRepository,
  type IdempotencyStore,
  type PayeeDirectory,
  type PaymentSettings,
  SYSTEM_ACTOR,
} from '@/ports/repositories'
import { type Clock, type IdGenerator } from '@/ports/system'
import { type AutoDebitCheck, loadAutoDebit } from '@/use-cases/auto-debit'
import {
  type BuildPaymentPlanDeps,
  makeBuildPaymentPlan,
} from '@/use-cases/build-payment-plan'
import {
  failureReason,
  makeConfirmationCheck,
  makeResolveInFlight,
} from '@/use-cases/payment-guards'
import {
  type FundingSummary,
  makeReserveFunding,
} from '@/use-cases/reserve-funding'
import { requireEntityById } from '@/use-cases/shared'

export type RunPaymentLadderDeps = BuildPaymentPlanDeps & {
  bills: BillRepository
  payees: PayeeDirectory
  idempotency: IdempotencyStore
  audit: AuditLog
  railStatus: ReadonlyMap<RailId, RailStatusReader>
  fundings: FundingRepository
  funder: ReserveFunder
  documents: DocumentStore
  clock: Clock
  ids: IdGenerator
}

export type LadderRun = {
  bill: Bill
  plan: PaymentPlan
  attempts: PaymentAttempt[]
  instructions: AssistedInstructions | null
}

export type LadderOptions = { confirmed?: boolean; actor?: Actor }

const READY: readonly BillStatus[] = ['OPEN', 'NEEDS_CONFIRMATION']
const RESUMABLE: readonly BillStatus[] = ['OPEN', 'PROCESSING']

export function assistedInstructions(bill: Bill): AssistedInstructions {
  return {
    kind: bill.kind,
    copyCode: bill.code,
    pixCode: bill.pixCode,
    amountCents: bill.amount.cents,
    dueDate: bill.dueDate,
  }
}

const failed = (reason: string): RailResult => ({ outcome: 'FAILED', reason })

// The personal entity pays Asaas bills from money the reserve moves in first.
export function needsReserve(
  entity: FinancialEntity,
  step: PaymentStep,
): boolean {
  return (
    entity.kind === 'PF' && step.rail === 'ASAAS' && step.mode === 'AUTOMATIC'
  )
}

type Run = {
  tenantId: string
  bill: Bill
  entity: FinancialEntity
  settings: PaymentSettings
  today: LocalDate
  actor: Actor
  confirmed: boolean
}

export function makeRunPaymentLadder(deps: RunPaymentLadderDeps) {
  const buildPlan = makeBuildPaymentPlan(deps)
  const confirmationReasons = makeConfirmationCheck(deps)
  const resolveInFlight = makeResolveInFlight(deps)
  const funding = makeReserveFunding(deps)

  function event(
    run: Run,
    fields: Pick<AuditEvent, 'action' | 'rail' | 'result' | 'details'>,
  ): AuditEvent {
    return {
      id: deps.ids.next(),
      tenantId: run.tenantId,
      actor: run.actor.kind,
      actorId: run.actor.id,
      requestId: run.actor.requestId,
      subjectId: run.bill.id,
      at: deps.clock.now(),
      ...fields,
    }
  }

  // Per payment and per entity caps bound what moves without a human; a bank
  // approval step is already approved by one, so only the rail cap applies.
  async function capFailure(
    run: Run,
    step: PaymentStep,
  ): Promise<string | null> {
    const { tenantId, bill, settings, today } = run
    const cents = bill.amount.cents
    const automatic = step.mode === 'AUTOMATIC'
    const paymentCap = automatic ? settings.paymentCapCents : null
    if (paymentCap !== null && cents > paymentCap) {
      return 'PAYMENT_CAP_EXCEEDED'
    }
    const railCap = settings.dailyCapCents[step.rail]
    const committedOn = (rail?: RailId) =>
      deps.payments.committedCents(tenantId, bill.entityId, today, rail)
    if (
      railCap !== undefined &&
      (await committedOn(step.rail)) + cents > railCap
    ) {
      return 'DAILY_CAP_EXCEEDED'
    }
    const entityCap = automatic ? settings.entityDailyCapCents : null
    if (entityCap !== null && (await committedOn()) + cents > entityCap) {
      return 'ENTITY_DAILY_CAP_EXCEEDED'
    }
    return null
  }

  function attemptFor(
    run: Run,
    plan: PaymentPlan,
    result: RailResult,
    id: string,
  ): PaymentAttempt {
    const step = currentStep(plan)
    return {
      id,
      billId: run.bill.id,
      stepIndex: plan.currentStep,
      rail: step.rail,
      mode: step.mode,
      method: step.method,
      amount: run.bill.amount,
      outcome: result.outcome,
      reason: result.reason ?? null,
      externalId: result.externalId ?? null,
      idempotencyKey: idempotencyKey(
        run.bill.id,
        plan.currentStep,
        step.method,
      ),
      at: deps.clock.now(),
    }
  }

  // Only an error that proves nothing was sent moves down; any other throw may
  // have paid, so the attempt stays in flight until the rail says otherwise.
  async function callRail(
    rail: PaymentRail,
    run: Run,
    step: PaymentStep,
    key: string,
  ): Promise<RailResult> {
    try {
      return await rail.pay({
        bill: run.bill,
        mode: step.mode,
        method: step.method,
        idempotencyKey: key,
      })
    } catch (error) {
      const outcome =
        error instanceof ProviderNotConfiguredError ? 'FAILED' : 'IN_FLIGHT'
      return { outcome, reason: failureReason(error) }
    }
  }

  // Assisted is the terminal step and is resolved here, never by a rail, so it
  // cannot fail. Null means another run holds this payment.
  async function attemptStep(
    run: Run,
    plan: PaymentPlan,
  ): Promise<RailResult | null> {
    const step = currentStep(plan)
    if (step.mode === 'ASSISTED') {
      return {
        outcome: 'ASSISTED',
        instructions: assistedInstructions(run.bill),
      }
    }
    const rail = deps.rails.get(step.rail)
    if (!rail) {
      return failed('RAIL_UNAVAILABLE')
    }
    const key = idempotencyKey(run.bill.id, plan.currentStep, step.method)
    const previous = await deps.idempotency.find<RailResult>(run.tenantId, key)
    if (previous) {
      return previous
    }
    const capped = await capFailure(run, step)
    if (capped) {
      return failed(capped)
    }
    const unfunded = needsReserve(run.entity, step)
      ? await funding.ensureFunded(run.tenantId, run.bill, run.actor)
      : null
    if (unfunded) {
      return failed(unfunded)
    }
    await deps.payments.savePlan(run.tenantId, plan)
    const claim = attemptFor(
      run,
      plan,
      { outcome: 'IN_FLIGHT' },
      `${key}:claim`,
    )
    if (!(await deps.payments.claimAttempt(run.tenantId, claim))) {
      return null
    }
    const result = await callRail(rail, run, step, key)
    if (result.outcome !== 'IN_FLIGHT') {
      await deps.idempotency.save(run.tenantId, key, 'payment', result)
    }
    return result
  }

  // The claim row already says IN_FLIGHT, so an unresolved call adds no row.
  async function record(
    run: Run,
    plan: PaymentPlan,
    result: RailResult,
  ): Promise<PaymentAttempt> {
    const attempt = attemptFor(run, plan, result, deps.ids.next())
    if (result.outcome !== 'IN_FLIGHT') {
      await deps.payments.addAttempt(run.tenantId, attempt)
    }
    await deps.audit.record(
      event(run, {
        action: 'payment.attempt',
        rail: attempt.rail,
        result: result.outcome,
        details: {
          stepIndex: attempt.stepIndex,
          method: attempt.method,
          reason: attempt.reason,
          idempotencyKey: attempt.idempotencyKey,
          externalId: attempt.externalId,
        },
      }),
    )
    return attempt
  }

  async function finish(
    run: Run,
    plan: PaymentPlan,
    attempts: PaymentAttempt[],
    result: RailResult,
  ): Promise<LadderRun> {
    const ready = transitionBill(run.bill, 'OPEN')
    const finished =
      result.outcome === 'PAID'
        ? markBillPaid(ready, 'RAIL', deps.clock.now())
        : transitionBill(ready, billStatusFor(result.outcome))
    await deps.bills.save(finished)
    await deps.payments.savePlan(run.tenantId, plan)
    for (const key of run.confirmed ? recipientKeys(run.bill) : []) {
      await deps.payees.remember(run.tenantId, run.bill.entityId, key)
    }
    return {
      bill: finished,
      plan,
      attempts,
      instructions: result.instructions ?? null,
    }
  }

  async function walk(
    run: Run,
    plan: PaymentPlan,
    first?: RailResult,
  ): Promise<LadderRun> {
    const attempts: PaymentAttempt[] = []
    let current = plan
    let result = first ?? (await attemptStep(run, current))
    while (result?.outcome === 'FAILED') {
      attempts.push(await record(run, current, result))
      current = moveDown(current)
      result = await attemptStep(run, current)
    }
    if (!result) {
      return { bill: run.bill, plan: current, attempts, instructions: null }
    }
    attempts.push(await record(run, current, result))
    return finish(run, current, attempts, result)
  }

  // A payment whose answer was lost is never sent again: the rail is asked
  // what happened, and until it answers the bill waits as processing.
  async function resume(
    run: Run,
    plan: PaymentPlan,
    pending: PaymentAttempt,
  ): Promise<LadderRun> {
    const at = { ...plan, currentStep: pending.stepIndex }
    const result = await resolveInFlight(
      run.tenantId,
      run.bill.entityId,
      pending,
    )
    if (result) {
      return walk(run, at, result)
    }
    const waiting = transitionBill(run.bill, 'PROCESSING')
    await deps.bills.save(waiting)
    await deps.audit.record(
      event(run, {
        action: 'payment.in_flight',
        rail: pending.rail,
        result: 'IN_FLIGHT',
        details: { idempotencyKey: pending.idempotencyKey },
      }),
    )
    return { bill: waiting, plan: at, attempts: [], instructions: null }
  }

  async function leaveToBank(run: Run, plan: PaymentPlan): Promise<LadderRun> {
    const open = transitionBill(run.bill, 'OPEN')
    if (open !== run.bill) {
      await deps.bills.save(open)
    }
    await deps.audit.record(
      event(run, {
        action: 'payment.left_to_auto_debit',
        rail: null,
        result: 'AUTO_DEBIT',
        details: { recipients: recipientKeys(run.bill) },
      }),
    )
    return { bill: open, plan, attempts: [], instructions: null }
  }

  async function askForConfirmation(
    run: Run,
    plan: PaymentPlan,
    reasons: readonly string[],
  ): Promise<LadderRun> {
    const pending = transitionBill(run.bill, 'NEEDS_CONFIRMATION')
    await deps.bills.save(pending)
    await deps.audit.record(
      event(run, {
        action: 'payment.confirmation_requested',
        rail: currentStep(plan).rail,
        result: 'NEEDS_CONFIRMATION',
        details: { reasons, recipients: recipientKeys(run.bill) },
      }),
    )
    return { bill: pending, plan, attempts: [], instructions: null }
  }

  return async function runPaymentLadder(
    tenantId: string,
    billId: string,
    options: LadderOptions = {},
  ): Promise<LadderRun> {
    const bill = await deps.bills.findById(tenantId, billId)
    if (!bill) {
      throw new NotFoundError('Bill')
    }
    const stored = await deps.payments.findPlan(tenantId, billId)
    const plan = stored ?? (await buildPlan(tenantId, bill))
    const previous = await deps.payments.listAttempts(tenantId, billId)
    const pending = RESUMABLE.includes(bill.status)
      ? inFlightAttempt(previous)
      : null
    const ready = READY.includes(bill.status) && !hasCommittedAttempt(previous)
    if (!pending && !ready) {
      return { bill, plan, attempts: [], instructions: null }
    }
    const settings = await deps.settings.get(tenantId, bill.entityId)
    const run: Run = {
      tenantId,
      bill,
      entity: await requireEntityById(deps.entities, tenantId, bill.entityId),
      settings,
      today: toLocalDate(deps.clock.now()),
      actor: options.actor ?? SYSTEM_ACTOR,
      confirmed: options.confirmed === true,
    }
    if (pending) {
      return resume(run, plan, pending)
    }
    const isAutoDebit = await loadAutoDebit(deps, tenantId)
    if (isAutoDebit(bill)) {
      return leaveToBank(run, plan)
    }
    const current = settings.killSwitch ? jumpToAssisted(plan) : plan
    const reasons =
      run.confirmed || isAtAssistedStep(current)
        ? []
        : await confirmationReasons(tenantId, bill, settings)
    if (reasons.length > 0) {
      return askForConfirmation(run, current, reasons)
    }
    return walk(run, current)
  }
}

export type PrepareFundingDeps = RunPaymentLadderDeps

// Picks the personal bills whose next step is Asaas and that would be paid
// right away, then funds them in one round per entity before the ladder runs.
export function makePrepareFunding(deps: PrepareFundingDeps) {
  const buildPlan = makeBuildPaymentPlan(deps)
  const confirmationReasons = makeConfirmationCheck(deps)
  const funding = makeReserveFunding(deps)

  async function fundable(
    tenantId: string,
    bill: Bill,
    isAutoDebit: AutoDebitCheck,
  ): Promise<boolean> {
    const entity = await deps.entities.findById(tenantId, bill.entityId)
    const settings = await deps.settings.get(tenantId, bill.entityId)
    if (!entity || settings.killSwitch || isAutoDebit(bill)) {
      return false
    }
    const attempts = await deps.payments.listAttempts(tenantId, bill.id)
    if (hasCommittedAttempt(attempts)) {
      return false
    }
    const plan =
      (await deps.payments.findPlan(tenantId, bill.id)) ??
      (await buildPlan(tenantId, bill))
    if (!needsReserve(entity, currentStep(plan))) {
      return false
    }
    const reasons = await confirmationReasons(tenantId, bill, settings)
    return reasons.length === 0
  }

  return async function prepareFunding(
    tenantId: string,
    bills: readonly Bill[],
  ): Promise<FundingSummary> {
    const isAutoDebit = await loadAutoDebit(deps, tenantId)
    const chosen: Bill[] = []
    for (const bill of bills) {
      if (await fundable(tenantId, bill, isAutoDebit)) {
        chosen.push(bill)
      }
    }
    return funding.fundDue(tenantId, chosen)
  }
}
