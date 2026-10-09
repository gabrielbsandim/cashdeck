import { describe, expect, it } from 'vitest'
import {
  ASSISTED_STEP,
  billStatusFor,
  createPaymentPlan,
  currentStep,
  hasCommittedAttempt,
  idempotencyKey,
  isAtAssistedStep,
  jumpToAssisted,
  methodFor,
  moveDown,
  type PaymentAttempt,
  type RailId,
  routePayment,
} from '@/payments/payment-plan'
import { type BillKind } from '@/bills/bill'
import { Money } from '@/money/money'

const anyRail = () => true
const only =
  (...rails: RailId[]) =>
  (rail: RailId) =>
    rails.includes(rail)
const route = (
  entityKind: 'PF' | 'PJ',
  billKind: BillKind,
  canUse: (rail: RailId, kind: BillKind) => boolean = anyRail,
  hasPixCode = false,
) => routePayment({ entityKind, billKind, hasPixCode }, canUse)
const steps = (found: ReturnType<typeof route>) =>
  found.map(step => `${step.mode}:${step.rail}:${step.method}`)

describe('createPaymentPlan', () => {
  it('requires the assisted step at the end, once', () => {
    expect(() => createPaymentPlan('b1', [])).toThrow(
      'end with the assisted step',
    )
    expect(() =>
      createPaymentPlan('b1', [
        { mode: 'AUTOMATIC', rail: 'ASAAS', method: 'BOLETO' },
      ]),
    ).toThrow('end with the assisted step')
    expect(() =>
      createPaymentPlan('b1', [ASSISTED_STEP, ASSISTED_STEP]),
    ).toThrow('from automatic to assisted')
  })

  it('requires steps ordered from automatic to assisted', () => {
    expect(() =>
      createPaymentPlan('b1', [
        { mode: 'BANK_APPROVAL', rail: 'C6_EMPRESAS', method: 'BOLETO' },
        { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS', method: 'BOLETO' },
        ASSISTED_STEP,
      ]),
    ).toThrow('from automatic to assisted')
  })
})

describe('ladder movement', () => {
  const plan = createPaymentPlan('b1', [
    { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS', method: 'BOLETO' },
    { mode: 'BANK_APPROVAL', rail: 'C6_EMPRESAS', method: 'BOLETO' },
    ASSISTED_STEP,
  ])

  it('moves down one step at a time and stops at assisted', () => {
    expect(currentStep(plan).rail).toBe('INTER_EMPRESAS')
    const second = moveDown(plan)
    expect(currentStep(second).mode).toBe('BANK_APPROVAL')
    const third = moveDown(second)
    expect(isAtAssistedStep(third)).toBe(true)
    expect(moveDown(third).currentStep).toBe(2)
    expect(jumpToAssisted(plan).currentStep).toBe(2)
  })

  it('falls back to assisted for an out of range step', () => {
    expect(currentStep({ ...plan, currentStep: 9 })).toEqual(ASSISTED_STEP)
  })

  it('derives keys and statuses', () => {
    expect(idempotencyKey('b1', 1, 'PIX')).toBe('b1:1:PIX')
    expect(methodFor('PIX_KEY')).toBe('PIX')
    expect(methodFor('TAX_BARCODE')).toBe('BOLETO')
    expect(billStatusFor('SUBMITTED')).toBe('PROCESSING')
    expect(billStatusFor('PENDING_APPROVAL')).toBe('AWAITING_BANK_APPROVAL')
    expect(billStatusFor('FAILED')).toBe('OPEN')
    expect(billStatusFor('IN_FLIGHT')).toBe('PROCESSING')
  })
})

describe('hasCommittedAttempt', () => {
  const attempt = (outcome: PaymentAttempt['outcome']): PaymentAttempt => ({
    id: outcome,
    billId: 'b1',
    stepIndex: 0,
    rail: 'ASAAS',
    mode: 'AUTOMATIC',
    method: 'PIX',
    amount: Money.of(100),
    outcome,
    reason: null,
    externalId: null,
    idempotencyKey: 'k',
    at: new Date(0),
  })

  it('treats a paid or pending attempt as committed', () => {
    expect(hasCommittedAttempt([])).toBe(false)
    expect(hasCommittedAttempt([attempt('FAILED'), attempt('ASSISTED')])).toBe(
      false,
    )
    expect(hasCommittedAttempt([attempt('FAILED'), attempt('PAID')])).toBe(true)
    expect(hasCommittedAttempt([attempt('SUBMITTED')])).toBe(true)
    expect(hasCommittedAttempt([attempt('PENDING_APPROVAL')])).toBe(true)
  })
})

describe('routePayment', () => {
  it('routes personal bills', () => {
    expect(steps(route('PF', 'PIX_KEY'))).toEqual([
      'AUTOMATIC:MERCADO_PAGO_PAYOUTS:PIX',
      'AUTOMATIC:ASAAS:PIX',
      'ASSISTED:ASSISTED:PIX',
    ])
    expect(
      steps(route('PF', 'PIX_KEY', rail => rail !== 'MERCADO_PAGO_PAYOUTS')),
    ).toEqual(['AUTOMATIC:ASAAS:PIX', 'ASSISTED:ASSISTED:PIX'])
    expect(steps(route('PF', 'BOLETO'))).toEqual([
      'AUTOMATIC:ASAAS:BOLETO',
      'ASSISTED:ASSISTED:BOLETO',
    ])
    expect(route('PF', 'TAX_BARCODE')).toEqual([ASSISTED_STEP])
  })

  it('routes company bills and skips disabled rails', () => {
    expect(steps(route('PJ', 'BOLETO'))).toEqual([
      'AUTOMATIC:INTER_EMPRESAS:BOLETO',
      'BANK_APPROVAL:C6_EMPRESAS:BOLETO',
      'ASSISTED:ASSISTED:BOLETO',
    ])
    expect(steps(route('PJ', 'BOLETO', only('C6_EMPRESAS')))).toEqual([
      'BANK_APPROVAL:C6_EMPRESAS:BOLETO',
      'ASSISTED:ASSISTED:BOLETO',
    ])
    expect(route('PJ', 'DARF_NO_BARCODE', () => false)).toEqual([ASSISTED_STEP])
  })

  it('tries Pix first when a barcode bill carries a BR Code', () => {
    expect(steps(route('PF', 'BOLETO', anyRail, true))).toEqual([
      'AUTOMATIC:ASAAS:PIX',
      'AUTOMATIC:ASAAS:BOLETO',
      'ASSISTED:ASSISTED:PIX',
    ])
    expect(steps(route('PJ', 'BOLETO', anyRail, true))).toEqual([
      'AUTOMATIC:INTER_EMPRESAS:PIX',
      'AUTOMATIC:INTER_EMPRESAS:BOLETO',
      'BANK_APPROVAL:C6_EMPRESAS:BOLETO',
      'ASSISTED:ASSISTED:PIX',
    ])
    expect(steps(route('PJ', 'TAX_BARCODE', anyRail, true))).toEqual([
      'AUTOMATIC:INTER_EMPRESAS:PIX',
      'AUTOMATIC:INTER_EMPRESAS:BOLETO',
      'ASSISTED:ASSISTED:PIX',
    ])
    expect(steps(route('PF', 'PIX_QR', anyRail, true))).toEqual([
      'AUTOMATIC:ASAAS:PIX',
      'ASSISTED:ASSISTED:PIX',
    ])
  })

  it('asks the rail filter for the kind each step pays', () => {
    const pixOnly = (_rail: RailId, kind: BillKind) => kind === 'PIX_QR'
    expect(steps(route('PJ', 'BOLETO', pixOnly, true))).toEqual([
      'AUTOMATIC:INTER_EMPRESAS:PIX',
      'ASSISTED:ASSISTED:PIX',
    ])
  })
})
