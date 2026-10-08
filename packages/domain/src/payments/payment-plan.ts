import { type BillKind, type BillStatus } from '@/bills/bill'
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

export type PaymentStep = { readonly mode: StepMode; readonly rail: RailId }

export const ASSISTED_STEP: PaymentStep = { mode: 'ASSISTED', rail: 'ASSISTED' }

export type PaymentPlan = {
  readonly billId: string
  readonly steps: readonly PaymentStep[]
  readonly currentStep: number
}

export type AttemptOutcome =
  | 'PAID'
  | 'SUBMITTED'
  | 'PENDING_APPROVAL'
  | 'ASSISTED'
  | 'FAILED'

export type PaymentAttempt = {
  readonly id: string
  readonly billId: string
  readonly stepIndex: number
  readonly rail: RailId
  readonly mode: StepMode
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

export function idempotencyKey(billId: string, stepIndex: number): string {
  return `${billId}:${stepIndex}`
}

const STATUS_BY_OUTCOME: Record<AttemptOutcome, BillStatus> = {
  PAID: 'PAID',
  SUBMITTED: 'PROCESSING',
  PENDING_APPROVAL: 'AWAITING_BANK_APPROVAL',
  ASSISTED: 'ASSISTED',
  FAILED: 'OPEN',
}

export function billStatusFor(outcome: AttemptOutcome): BillStatus {
  return STATUS_BY_OUTCOME[outcome]
}

const auto = (rail: RailId): PaymentStep => ({ mode: 'AUTOMATIC', rail })
const approval = (rail: RailId): PaymentStep => ({
  mode: 'BANK_APPROVAL',
  rail,
})

const DEFAULT_ROUTES: Record<
  EntityKind,
  Record<BillKind, readonly PaymentStep[]>
> = {
  PF: {
    PIX_KEY: [auto('MERCADO_PAGO_PAYOUTS')],
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

export function routePayment(
  entityKind: EntityKind,
  billKind: BillKind,
  enabledRails: ReadonlySet<RailId>,
): PaymentStep[] {
  const steps = DEFAULT_ROUTES[entityKind][billKind].filter(step =>
    enabledRails.has(step.rail),
  )
  return [...steps, ASSISTED_STEP]
}
