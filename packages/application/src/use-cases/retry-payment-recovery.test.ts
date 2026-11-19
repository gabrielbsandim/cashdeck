import { describe, expect, it } from 'vitest'
import {
  ASSISTED_STEP,
  createBill,
  Money,
  type PaymentStep,
} from '@cashdeck/domain'
import { type Actor } from '@/ports/repositories'
import { FakePaymentRail } from '@/testing/providers'
import {
  BOLETO_BARCODE,
  NOW,
  scenario,
  TENANT,
  trust,
} from '@/testing/scenario.test-helpers'
import { makeRetryPayment } from '@/use-cases/retry-payment'

const ACTOR: Actor = { kind: 'USER', id: 'session:s1', requestId: null }
const AUTO: PaymentStep = {
  mode: 'AUTOMATIC',
  rail: 'INTER_EMPRESAS',
  method: 'BOLETO',
}

async function setup() {
  const rail = new FakePaymentRail('INTER_EMPRESAS')
  const deps = scenario([rail])
  const bill = {
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
    status: 'ASSISTED' as const,
  }
  await deps.bills.save(bill)
  await trust(deps.payees, bill)
  await deps.payments.savePlan(TENANT, {
    billId: 'b1',
    steps: [AUTO, ASSISTED_STEP],
    currentStep: 1,
    round: 0,
  })
  return { deps, rail, retry: makeRetryPayment(deps) }
}

describe('retryPayment after a failed write', () => {
  it('lets the next retry run when the plan write failed', async () => {
    const { deps, rail, retry } = await setup()
    const savePlan = deps.payments.savePlan.bind(deps.payments)
    let failures = 0
    deps.payments.savePlan = async (tenantId, plan) => {
      if (plan.currentStep === 0 && failures === 0) {
        failures += 1
        throw new Error('timeout')
      }
      await savePlan(tenantId, plan)
    }
    await expect(retry(TENANT, 'b1', { actor: ACTOR })).rejects.toThrow(
      'timeout',
    )
    expect(await deps.payments.findPlan(TENANT, 'b1')).toMatchObject({
      round: 1,
      currentStep: 1,
    })

    const run = await retry(TENANT, 'b1', { actor: ACTOR })
    expect(rail.requests.map(r => r.idempotencyKey)).toEqual(['b1:r2:0:BOLETO'])
    expect(run.bill.status).toBe('PAID')
  })

  it('lets the next retry run when reopening the bill failed', async () => {
    const { deps, rail, retry } = await setup()
    const save = deps.bills.save.bind(deps.bills)
    let failures = 0
    deps.bills.save = async bill => {
      if (bill.status === 'OPEN' && failures === 0) {
        failures += 1
        throw new Error('timeout')
      }
      await save(bill)
    }
    await expect(retry(TENANT, 'b1', { actor: ACTOR })).rejects.toThrow(
      'timeout',
    )
    expect((await deps.bills.findById(TENANT, 'b1'))?.status).toBe('ASSISTED')

    const run = await retry(TENANT, 'b1', { actor: ACTOR })
    expect(rail.requests.map(r => r.idempotencyKey)).toEqual(['b1:r2:0:BOLETO'])
    expect(run.bill.status).toBe('PAID')
  })
})
