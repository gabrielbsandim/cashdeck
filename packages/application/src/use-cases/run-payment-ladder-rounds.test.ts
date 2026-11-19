import { describe, expect, it } from 'vitest'
import {
  ASSISTED_STEP,
  createBill,
  Money,
  type Bill,
  type PaymentAttempt,
  type PaymentStep,
} from '@cashdeck/domain'
import { FakePaymentRail } from '@/testing/providers'
import {
  BOLETO_BARCODE,
  NOW,
  scenario,
  TENANT,
  trust,
} from '@/testing/scenario.test-helpers'
import { makeRunPaymentLadder } from '@/use-cases/run-payment-ladder'

const AUTO: PaymentStep = {
  mode: 'AUTOMATIC',
  rail: 'INTER_EMPRESAS',
  method: 'BOLETO',
}

const bill = (overrides: Partial<Bill> = {}): Bill => ({
  ...createBill({
    id: 'b1',
    tenantId: TENANT,
    entityId: 'pj',
    kind: 'BOLETO',
    source: 'MANUAL',
    payee: 'Supplier',
    amount: Money.of(12345),
    dueDate: '2026-10-20',
    code: BOLETO_BARCODE,
    createdAt: NOW,
  }),
  ...overrides,
})

const attempt = (overrides: Partial<PaymentAttempt> = {}): PaymentAttempt => ({
  id: 'b1:0:BOLETO:claim',
  billId: 'b1',
  stepIndex: 0,
  rail: 'INTER_EMPRESAS',
  mode: 'AUTOMATIC',
  method: 'BOLETO',
  amount: Money.of(12345),
  outcome: 'IN_FLIGHT',
  reason: null,
  externalId: null,
  idempotencyKey: 'b1:0:BOLETO',
  at: NOW,
  ...overrides,
})

describe('runPaymentLadder rounds', () => {
  const roundOne = async (
    status: Bill['status'],
    attempts: PaymentAttempt[],
  ) => {
    const rail = new FakePaymentRail('INTER_EMPRESAS')
    const deps = scenario([rail])
    const seed = bill({ status })
    await deps.bills.save(seed)
    await trust(deps.payees, seed)
    await deps.payments.savePlan(TENANT, {
      billId: 'b1',
      steps: [AUTO, ASSISTED_STEP],
      currentStep: 0,
      round: 1,
    })
    for (const row of attempts) {
      await deps.payments.addAttempt(TENANT, row)
    }
    return { deps, rail, run: makeRunPaymentLadder(deps) }
  }

  it('builds the key of a stored round 1 plan with the round', async () => {
    const { rail, run } = await roundOne('OPEN', [])
    const result = await run(TENANT, 'b1', { confirmed: true })
    expect(rail.requests[0]?.idempotencyKey).toBe('b1:r1:0:BOLETO')
    expect(result.attempts[0]?.idempotencyKey).toBe('b1:r1:0:BOLETO')
  })

  it('resumes an in-flight attempt of round 1 with the round in its key', async () => {
    const { deps, rail, run } = await roundOne('PROCESSING', [
      attempt({
        id: 'b1:r1:0:BOLETO:claim',
        idempotencyKey: 'b1:r1:0:BOLETO',
      }),
    ])
    await deps.idempotency.save(TENANT, 'b1:r1:0:BOLETO', 'payment', {
      outcome: 'SUBMITTED',
      externalId: 'stored',
    })
    const result = await run(TENANT, 'b1')
    expect(rail.requests).toHaveLength(0)
    expect(result.bill.status).toBe('PROCESSING')
    expect(result.attempts[0]).toMatchObject({
      idempotencyKey: 'b1:r1:0:BOLETO',
      externalId: 'stored',
    })
  })
})
