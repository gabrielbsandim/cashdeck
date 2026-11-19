import { describe, expect, it } from 'vitest'
import {
  ASSISTED_STEP,
  createBill,
  Money,
  type PaymentStep,
} from '@cashdeck/domain'
import { RetryRefusedError } from '@/errors/errors'
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

async function setup(stored = true) {
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
  if (stored) {
    await deps.payments.savePlan(TENANT, {
      billId: 'b1',
      steps: [AUTO, ASSISTED_STEP],
      currentStep: 1,
      round: 0,
    })
  }
  return { deps, rail, retry: makeRetryPayment(deps) }
}

const reasonOf = (error: unknown) => (error as RetryRefusedError).reason

describe('retryPayment races', () => {
  it('refuses a retry that reads the plan another retry just restarted', async () => {
    const { deps, rail, retry } = await setup()
    const savePlan = deps.payments.savePlan.bind(deps.payments)
    let late: unknown = null
    deps.payments.savePlan = async (tenantId, plan) => {
      await savePlan(tenantId, plan)
      if (plan.round === 1 && late === null) {
        late = await retry(TENANT, 'b1', { actor: ACTOR }).catch(e => e)
      }
    }
    const run = await retry(TENANT, 'b1', { actor: ACTOR })

    expect(late).toBeInstanceOf(RetryRefusedError)
    expect(reasonOf(late)).toBe('NOT_ASSISTED')
    expect(rail.requests.map(r => r.idempotencyKey)).toEqual(['b1:r1:0:BOLETO'])
    expect(run.bill.status).toBe('PAID')
    expect((await deps.bills.findById(TENANT, 'b1'))?.status).toBe('PAID')
  })

  it('refuses a retry that read the old plan after the round was claimed', async () => {
    const { deps, rail, retry } = await setup()
    const claim = deps.idempotency.claim.bind(deps.idempotency)
    let late: unknown = null
    deps.idempotency.claim = async (tenantId, key, scope, result) => {
      const won = await claim(tenantId, key, scope, result)
      if (won && late === null) {
        late = await retry(TENANT, 'b1', { actor: ACTOR }).catch(e => e)
      }
      return won
    }
    await retry(TENANT, 'b1', { actor: ACTOR })

    expect(reasonOf(late)).toBe('NOT_ASSISTED')
    expect(rail.requests).toHaveLength(1)
    expect(await deps.payments.findPlan(TENANT, 'b1')).toMatchObject({
      round: 1,
    })
    expect((await deps.bills.findById(TENANT, 'b1'))?.status).toBe('PAID')
  })

  it('refuses a bill with no stored plan and writes none', async () => {
    const { deps, rail, retry } = await setup(false)
    const failure = await retry(TENANT, 'b1', { actor: ACTOR }).catch(e => e)
    expect(reasonOf(failure)).toBe('NOT_ASSISTED')
    expect(rail.requests).toHaveLength(0)
    expect(await deps.payments.findPlan(TENANT, 'b1')).toBeNull()
  })
})
