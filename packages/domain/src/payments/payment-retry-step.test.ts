import { describe, expect, it } from 'vitest'
import { createBill, transitionBill } from '@/bills/bill'
import { Money } from '@/money/money'
import {
  ASSISTED_STEP,
  createPaymentPlan,
  retryBlock,
} from '@/payments/payment-plan'

describe('retryBlock and the step the plan is on', () => {
  it('refuses a plan a retry already moved off the assisted step', () => {
    const bill = transitionBill(
      createBill({
        id: 'b1',
        tenantId: 't1',
        entityId: 'e1',
        kind: 'BOLETO',
        source: 'MANUAL',
        amount: Money.of(1000),
        dueDate: '2026-10-20',
        code: '123',
        createdAt: new Date('2026-10-08T12:00:00Z'),
      }),
      'ASSISTED',
    )
    const plan = {
      ...createPaymentPlan('b1', [
        { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS', method: 'BOLETO' },
        ASSISTED_STEP,
      ]),
      round: 1,
    }
    expect(retryBlock({ bill, plan, attempts: [], killSwitch: false })).toBe(
      'NOT_ASSISTED',
    )
  })
})
