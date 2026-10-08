import { describe, expect, it } from 'vitest'
import {
  ASSISTED_STEP,
  billStatusFor,
  createPaymentPlan,
  currentStep,
  idempotencyKey,
  isAtAssistedStep,
  jumpToAssisted,
  moveDown,
  type RailId,
  routePayment,
} from '@/payments/payment-plan'

const allRails = new Set<RailId>([
  'MERCADO_PAGO_PAYOUTS',
  'ASAAS',
  'INTER_EMPRESAS',
  'C6_EMPRESAS',
])

describe('createPaymentPlan', () => {
  it('requires the assisted step at the end, once', () => {
    expect(() => createPaymentPlan('b1', [])).toThrow(
      'end with the assisted step',
    )
    expect(() =>
      createPaymentPlan('b1', [{ mode: 'AUTOMATIC', rail: 'ASAAS' }]),
    ).toThrow('end with the assisted step')
    expect(() =>
      createPaymentPlan('b1', [ASSISTED_STEP, ASSISTED_STEP]),
    ).toThrow('from automatic to assisted')
  })

  it('requires steps ordered from automatic to assisted', () => {
    expect(() =>
      createPaymentPlan('b1', [
        { mode: 'BANK_APPROVAL', rail: 'C6_EMPRESAS' },
        { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS' },
        ASSISTED_STEP,
      ]),
    ).toThrow('from automatic to assisted')
  })
})

describe('ladder movement', () => {
  const plan = createPaymentPlan('b1', [
    { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS' },
    { mode: 'BANK_APPROVAL', rail: 'C6_EMPRESAS' },
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
    expect(idempotencyKey('b1', 1)).toBe('b1:1')
    expect(billStatusFor('SUBMITTED')).toBe('PROCESSING')
    expect(billStatusFor('PENDING_APPROVAL')).toBe('AWAITING_BANK_APPROVAL')
    expect(billStatusFor('FAILED')).toBe('OPEN')
  })
})

describe('routePayment', () => {
  it('routes personal bills', () => {
    expect(routePayment('PF', 'PIX_KEY', allRails).map(s => s.rail)).toEqual([
      'MERCADO_PAGO_PAYOUTS',
      'ASSISTED',
    ])
    expect(routePayment('PF', 'BOLETO', allRails).map(s => s.rail)).toEqual([
      'ASAAS',
      'ASSISTED',
    ])
    expect(routePayment('PF', 'TAX_BARCODE', allRails)).toEqual([ASSISTED_STEP])
  })

  it('routes company bills and skips disabled rails', () => {
    expect(routePayment('PJ', 'BOLETO', allRails).map(s => s.mode)).toEqual([
      'AUTOMATIC',
      'BANK_APPROVAL',
      'ASSISTED',
    ])
    expect(
      routePayment('PJ', 'BOLETO', new Set<RailId>(['C6_EMPRESAS'])).map(
        s => s.rail,
      ),
    ).toEqual(['C6_EMPRESAS', 'ASSISTED'])
    expect(routePayment('PJ', 'DARF_NO_BARCODE', new Set())).toEqual([
      ASSISTED_STEP,
    ])
  })
})
