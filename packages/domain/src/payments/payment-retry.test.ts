import { describe, expect, it } from 'vitest'
import { createBill, transitionBill, type Bill } from '@/bills/bill'
import { Money } from '@/money/money'
import {
  ASSISTED_STEP,
  createPaymentPlan,
  idempotencyKey,
  restartPlan,
  retryBlock,
  type PaymentAttempt,
  type PaymentPlan,
  type PaymentStep,
} from '@/payments/payment-plan'

const AUTO: PaymentStep = {
  mode: 'AUTOMATIC',
  rail: 'INTER_EMPRESAS',
  method: 'BOLETO',
}

const NOW = new Date('2026-10-08T12:00:00Z')

const assistedBill = (): Bill =>
  transitionBill(
    createBill({
      id: 'b1',
      tenantId: 't1',
      entityId: 'e1',
      kind: 'BOLETO',
      source: 'MANUAL',
      amount: Money.of(1000),
      dueDate: '2026-10-20',
      code: '123',
      createdAt: NOW,
    }),
    'ASSISTED',
  )

const plan = (steps: PaymentStep[] = [AUTO, ASSISTED_STEP]): PaymentPlan => ({
  ...createPaymentPlan('b1', steps),
  currentStep: steps.length - 1,
})

const attempt = (
  outcome: PaymentAttempt['outcome'],
  reason: string | null = null,
  stepIndex = 0,
): PaymentAttempt => ({
  id: `a-${outcome}-${stepIndex}`,
  billId: 'b1',
  stepIndex,
  rail: 'INTER_EMPRESAS',
  mode: 'AUTOMATIC',
  method: 'BOLETO',
  amount: Money.of(1000),
  outcome,
  reason,
  externalId: null,
  idempotencyKey: `b1:${stepIndex}:BOLETO`,
  at: NOW,
})

const block = (overrides: Partial<Parameters<typeof retryBlock>[0]> = {}) =>
  retryBlock({
    bill: assistedBill(),
    plan: plan(),
    attempts: [attempt('IN_FLIGHT'), attempt('FAILED', 'Saldo insuficiente')],
    killSwitch: false,
    ...overrides,
  })

describe('idempotencyKey rounds', () => {
  it('keeps round 0 byte-identical to the key used before rounds existed', () => {
    expect(idempotencyKey('b', 0, 'BOLETO')).toBe('b:0:BOLETO')
    expect(idempotencyKey('b', 2, 'PIX', 0)).toBe('b:2:PIX')
  })

  it('prefixes the round from round 1 on', () => {
    expect(idempotencyKey('b', 0, 'BOLETO', 1)).toBe('b:r1:0:BOLETO')
    expect(idempotencyKey('b', 3, 'PIX', 12)).toBe('b:r12:3:PIX')
  })
})

describe('createPaymentPlan round', () => {
  it('starts at round 0', () => {
    expect(createPaymentPlan('b1', [AUTO, ASSISTED_STEP]).round).toBe(0)
  })
})

describe('restartPlan', () => {
  it('goes back to step 0 with the next round and keeps the steps', () => {
    const stored = { ...plan(), round: 2 }
    expect(restartPlan(stored)).toEqual({
      billId: 'b1',
      steps: [AUTO, ASSISTED_STEP],
      currentStep: 0,
      round: 3,
    })
    expect(stored.currentStep).toBe(1)
  })
})

describe('retryBlock', () => {
  it('lets an assisted bill with an automatic step and only failures retry', () => {
    expect(block()).toBeNull()
    expect(block({ attempts: [] })).toBeNull()
  })

  it('refuses a bill that is not assisted', () => {
    const open = { ...assistedBill(), status: 'OPEN' as const }
    expect(block({ bill: open })).toBe('NOT_ASSISTED')
  })

  it('refuses when an attempt is committed', () => {
    for (const outcome of ['PAID', 'SUBMITTED', 'PENDING_APPROVAL'] as const) {
      expect(block({ attempts: [attempt(outcome)] })).toBe('COMMITTED')
    }
  })

  it('refuses when the last answer of a payment is unknown', () => {
    for (const reason of ['IN_FLIGHT_UNRESOLVED', 'APPROVAL_EXPIRED']) {
      expect(
        block({ attempts: [attempt('IN_FLIGHT'), attempt('FAILED', reason)] }),
      ).toBe('OUTCOME_UNKNOWN')
    }
  })

  it('refuses a plan with nothing but the assisted step', () => {
    expect(block({ plan: plan([ASSISTED_STEP]) })).toBe('NO_AUTOMATIC_STEP')
  })

  it('accepts a plan whose only non-assisted step is bank approval', () => {
    const approval: PaymentStep = {
      mode: 'BANK_APPROVAL',
      rail: 'C6_EMPRESAS',
      method: 'BOLETO',
    }
    expect(block({ plan: plan([approval, ASSISTED_STEP]) })).toBeNull()
  })

  it('refuses while the kill switch is on', () => {
    expect(block({ killSwitch: true })).toBe('KILL_SWITCH')
  })
})
