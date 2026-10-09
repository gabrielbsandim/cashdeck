import { type BillKind, type BillStatus } from '@/bills/bill'
import { type LocalDate, toLocalDate } from '@/calendar/local-date'
import { type EntityKind } from '@/entities/financial-entity'
import { type Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'

export const STEP_MODES = ['AUTOMATIC', 'BANK_APPROVAL', 'ASSISTED'] as const
export type StepMode = (typeof STEP_MODES)[number]

export const RAIL_IDS = [
  'MERCADO_PAGO_PAYOUTS',
  'ASAAS',
  'INTER_EMPRESAS',
  'C6_EMPRESAS',
  'ASSISTED',
] as const
export type RailId = (typeof RAIL_IDS)[number]

export const PAYMENT_METHODS = ['PIX', 'BOLETO'] as const
// BOLETO covers every barcode payment, tax guides included.
export type PaymentMethod = (typeof PAYMENT_METHODS)[number]

export type PaymentStep = {
  readonly mode: StepMode
  readonly rail: RailId
  readonly method: PaymentMethod
}

export const ASSISTED_STEP: PaymentStep = {
  mode: 'ASSISTED',
  rail: 'ASSISTED',
  method: 'BOLETO',
}

export type PaymentPlan = {
  readonly billId: string
  readonly steps: readonly PaymentStep[]
  readonly currentStep: number
}

// IN_FLIGHT is written before a rail is called, so a crash mid-call leaves a
// trace that blocks a second payment until the rail reports what happened.
export type AttemptOutcome =
  | 'PAID'
  | 'SUBMITTED'
  | 'PENDING_APPROVAL'
  | 'ASSISTED'
  | 'FAILED'
  | 'IN_FLIGHT'

export type PaymentAttempt = {
  readonly id: string
  readonly billId: string
  readonly stepIndex: number
  readonly rail: RailId
  readonly mode: StepMode
  readonly method: PaymentMethod
  readonly amount: Money
  readonly outcome: AttemptOutcome
  readonly reason: string | null
  readonly externalId: string | null
  readonly idempotencyKey: string
  readonly at: Date
}

export function createPaymentPlan(
  billId: string,
  steps: readonly PaymentStep[],
): PaymentPlan {
  const last = steps.at(-1)
  if (last?.mode !== 'ASSISTED') {
    throw new ValidationError('A payment plan must end with the assisted step.')
  }
  const ranks = steps.map(step => STEP_MODES.indexOf(step.mode))
  const ordered = ranks
    .slice(1)
    .every((rank, index) => rank >= (ranks[index] as number))
  if (!ordered || steps.filter(step => step.mode === 'ASSISTED').length > 1) {
    throw new ValidationError(
      'Payment steps must go from automatic to assisted.',
    )
  }
  return { billId, steps, currentStep: 0 }
}

export function currentStep(plan: PaymentPlan): PaymentStep {
  return plan.steps[plan.currentStep] ?? ASSISTED_STEP
}

export function isAtAssistedStep(plan: PaymentPlan): boolean {
  return currentStep(plan).mode === 'ASSISTED'
}

// Moving down never goes past the assisted step: a bill is never left unpaid
// without a human path.
export function moveDown(plan: PaymentPlan): PaymentPlan {
  const lastIndex = plan.steps.length - 1
  return { ...plan, currentStep: Math.min(plan.currentStep + 1, lastIndex) }
}

export function jumpToAssisted(plan: PaymentPlan): PaymentPlan {
  return { ...plan, currentStep: plan.steps.length - 1 }
}

export function idempotencyKey(
  billId: string,
  stepIndex: number,
  method: PaymentMethod,
): string {
  return `${billId}:${stepIndex}:${method}`
}

const COMMITTED_OUTCOMES: readonly AttemptOutcome[] = [
  'PAID',
  'SUBMITTED',
  'PENDING_APPROVAL',
  'IN_FLIGHT',
]

// Attempts are append-only: a reconciled or resumed payment adds a row with the
// same idempotency key, so the last row of each key is its current state.
export function latestAttempts(
  attempts: readonly PaymentAttempt[],
): PaymentAttempt[] {
  const latest = new Map<string, PaymentAttempt>()
  for (const attempt of attempts) {
    latest.set(attempt.idempotencyKey, attempt)
  }
  return [...latest.values()]
}

// A bill can carry a Pix code and a barcode; once either rail took the money,
// or may still take it, no other step is tried.
export function hasCommittedAttempt(
  attempts: readonly PaymentAttempt[],
): boolean {
  return latestAttempts(attempts).some(attempt =>
    COMMITTED_OUTCOMES.includes(attempt.outcome),
  )
}

// The history a person reads: a claim row is noise once its call has answered.
export function attemptHistory(
  attempts: readonly PaymentAttempt[],
): PaymentAttempt[] {
  const latest = new Set(latestAttempts(attempts))
  return attempts.filter(
    attempt => attempt.outcome !== 'IN_FLIGHT' || latest.has(attempt),
  )
}

export function inFlightAttempt(
  attempts: readonly PaymentAttempt[],
): PaymentAttempt | null {
  return (
    latestAttempts(attempts).find(attempt => attempt.outcome === 'IN_FLIGHT') ??
    null
  )
}

// What a day already holds against a cap: every payment first tried that day
// whose current state may still move money, counted once per idempotency key.
export function committedCentsOn(
  attempts: readonly PaymentAttempt[],
  day: LocalDate,
): number {
  const firstDay = new Map<string, LocalDate>()
  for (const attempt of attempts) {
    if (!firstDay.has(attempt.idempotencyKey)) {
      firstDay.set(attempt.idempotencyKey, toLocalDate(attempt.at))
    }
  }
  return latestAttempts(attempts)
    .filter(attempt => firstDay.get(attempt.idempotencyKey) === day)
    .filter(attempt => COMMITTED_OUTCOMES.includes(attempt.outcome))
    .reduce((total, attempt) => total + attempt.amount.cents, 0)
}

const STATUS_BY_OUTCOME: Record<AttemptOutcome, BillStatus> = {
  PAID: 'PAID',
  SUBMITTED: 'PROCESSING',
  PENDING_APPROVAL: 'AWAITING_BANK_APPROVAL',
  ASSISTED: 'ASSISTED',
  FAILED: 'OPEN',
  IN_FLIGHT: 'PROCESSING',
}

export function billStatusFor(outcome: AttemptOutcome): BillStatus {
  return STATUS_BY_OUTCOME[outcome]
}

type Route = { readonly mode: StepMode; readonly rail: RailId }

const auto = (rail: RailId): Route => ({ mode: 'AUTOMATIC', rail })
const approval = (rail: RailId): Route => ({ mode: 'BANK_APPROVAL', rail })

// Each list is tried in order and a rail the entity has not authorized is
// skipped, so switching provider is authorizing one rail and removing another.
const DEFAULT_ROUTES: Record<EntityKind, Record<BillKind, readonly Route[]>> = {
  PF: {
    PIX_KEY: [auto('MERCADO_PAGO_PAYOUTS'), auto('ASAAS')],
    PIX_QR: [auto('ASAAS')],
    BOLETO: [auto('ASAAS')],
    TAX_BARCODE: [],
    DARF_NO_BARCODE: [],
  },
  PJ: {
    PIX_KEY: [auto('INTER_EMPRESAS'), approval('C6_EMPRESAS')],
    PIX_QR: [auto('INTER_EMPRESAS')],
    BOLETO: [auto('INTER_EMPRESAS'), approval('C6_EMPRESAS')],
    TAX_BARCODE: [auto('INTER_EMPRESAS')],
    DARF_NO_BARCODE: [auto('INTER_EMPRESAS')],
  },
}

const PIX_KINDS: readonly BillKind[] = ['PIX_KEY', 'PIX_QR']

export function methodFor(kind: BillKind): PaymentMethod {
  return PIX_KINDS.includes(kind) ? 'PIX' : 'BOLETO'
}

export type RouteInput = {
  entityKind: EntityKind
  billKind: BillKind
  hasPixCode: boolean
}

// The kind a rail is asked to support for a step: a Pix step on a barcode
// bill pays its BR Code, so the rail must take a Pix QR.
export type RailFilter = (rail: RailId, kind: BillKind) => boolean

export function routePayment(
  input: RouteInput,
  canUse: RailFilter,
): PaymentStep[] {
  const routes = DEFAULT_ROUTES[input.entityKind]
  const pixFirst = input.hasPixCode && methodFor(input.billKind) === 'BOLETO'
  const pix = pixFirst
    ? routes.PIX_QR.map(route => [route, 'PIX_QR'] as const)
    : []
  const own = routes[input.billKind].map(
    route => [route, input.billKind] as const,
  )
  const steps = [...pix, ...own]
    .filter(([route, kind]) => canUse(route.rail, kind))
    .map(
      ([route, kind]): PaymentStep => ({ ...route, method: methodFor(kind) }),
    )
  const assisted: PaymentStep = {
    ...ASSISTED_STEP,
    method: pixFirst ? 'PIX' : methodFor(input.billKind),
  }
  return [...steps, assisted]
}
