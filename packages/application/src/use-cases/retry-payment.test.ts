import { describe, expect, it } from 'vitest'
import {
  ASSISTED_STEP,
  createBill,
  Money,
  type Bill,
  type PaymentAttempt,
  type PaymentPlan,
  type PaymentStep,
} from '@cashdeck/domain'
import {
  ConflictError,
  NotFoundError,
  RetryRefusedError,
} from '@/errors/errors'
import { type Actor, type PaymentSettings } from '@/ports/repositories'
import { FakePaymentRail } from '@/testing/providers'
import {
  BOLETO_BARCODE,
  NOW,
  scenario,
  TENANT,
  trust,
} from '@/testing/scenario.test-helpers'
import { makeRetryPayment } from '@/use-cases/retry-payment'

const ACTOR: Actor = { kind: 'USER', id: 'session:s1', requestId: 'req-1' }
const AUTO: PaymentStep = {
  mode: 'AUTOMATIC',
  rail: 'INTER_EMPRESAS',
  method: 'BOLETO',
}
const TODAY = '2026-10-08'

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
  status: 'ASSISTED',
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

// The state the issue describes: the first rail refused for lack of balance
// and the bill fell to the assisted step.
const FELL_TO_ASSISTED: PaymentAttempt[] = [
  attempt(),
  attempt({
    id: 'a2',
    outcome: 'FAILED',
    reason: 'Saldo insuficiente',
  }),
  attempt({
    id: 'a3',
    stepIndex: 1,
    rail: 'ASSISTED',
    mode: 'ASSISTED',
    outcome: 'ASSISTED',
    idempotencyKey: 'b1:1:BOLETO',
  }),
]

type Seed = {
  seed?: Bill
  steps?: PaymentStep[]
  attempts?: PaymentAttempt[]
  settings?: Partial<PaymentSettings>
  rail?: FakePaymentRail
}

async function setup(options: Seed = {}) {
  const rail = options.rail ?? new FakePaymentRail('INTER_EMPRESAS')
  const deps = scenario([rail], options.settings)
  const seed = options.seed ?? bill()
  const steps = options.steps ?? [AUTO, ASSISTED_STEP]
  const plan: PaymentPlan = {
    billId: 'b1',
    steps,
    currentStep: steps.length - 1,
    round: 0,
  }
  await deps.bills.save(seed)
  await trust(deps.payees, seed)
  await deps.payments.savePlan(TENANT, plan)
  for (const row of options.attempts ?? FELL_TO_ASSISTED) {
    await deps.payments.addAttempt(TENANT, row)
  }
  await deps.idempotency.save(TENANT, 'b1:0:BOLETO', 'payment', {
    outcome: 'FAILED',
    reason: 'Saldo insuficiente',
  })
  return { deps, rail, seed, plan, retry: makeRetryPayment(deps) }
}

describe('retryPayment', () => {
  it('sends a bill that fell to assisted through round 1 and pays it', async () => {
    const { deps, rail, retry } = await setup()
    const run = await retry(TENANT, 'b1', { actor: ACTOR })

    expect(rail.requests).toHaveLength(1)
    expect(rail.requests[0]?.idempotencyKey).toBe('b1:r1:0:BOLETO')
    expect(run.bill.status).toBe('PAID')
    expect((await deps.bills.findById(TENANT, 'b1'))?.status).toBe('PAID')
    expect(await deps.payments.findPlan(TENANT, 'b1')).toMatchObject({
      round: 1,
      currentStep: 0,
    })
    expect(run.plan.round).toBe(1)
  })

  it('keeps the earlier attempts in history', async () => {
    const { deps, retry } = await setup()
    await retry(TENANT, 'b1', { actor: ACTOR })
    const all = await deps.payments.listAttempts(TENANT, 'b1')
    expect(all.map(a => a.id)).toEqual(
      expect.arrayContaining(['b1:0:BOLETO:claim', 'a2', 'a3']),
    )
    expect(all.map(a => a.idempotencyKey)).toEqual(
      expect.arrayContaining(['b1:0:BOLETO', 'b1:1:BOLETO', 'b1:r1:0:BOLETO']),
    )
    expect(all.at(-1)).toMatchObject({
      outcome: 'PAID',
      idempotencyKey: 'b1:r1:0:BOLETO',
    })
  })

  it('claims the new round under its own attempt id before calling the rail', async () => {
    const { deps, rail, retry } = await setup()
    let seen: string[] = []
    rail.pay = async () => {
      seen = (await deps.payments.listAttempts(TENANT, 'b1')).map(a => a.id)
      return { outcome: 'PAID', externalId: 'x' }
    }
    await retry(TENANT, 'b1', { actor: ACTOR })
    expect(seen).toContain('b1:r1:0:BOLETO:claim')
  })

  it('records the claim even when the rail throws', async () => {
    const rail = new FakePaymentRail('INTER_EMPRESAS').willReturn(
      new Error('socket hang up'),
    )
    const { deps, retry } = await setup({ rail })
    const run = await retry(TENANT, 'b1', { actor: ACTOR })
    expect(run.bill.status).toBe('PROCESSING')
    const claims = (await deps.payments.listAttempts(TENANT, 'b1')).filter(
      a => a.id === 'b1:r1:0:BOLETO:claim',
    )
    expect(claims).toHaveLength(1)
    expect(claims[0]?.outcome).toBe('IN_FLIGHT')
  })

  it('walks a second time down to assisted when the new round fails too', async () => {
    const rail = new FakePaymentRail('INTER_EMPRESAS').willReturn({
      outcome: 'FAILED',
      reason: 'Saldo insuficiente',
    })
    const { deps, retry } = await setup({ rail })
    const run = await retry(TENANT, 'b1', { actor: ACTOR })
    expect(run.bill.status).toBe('ASSISTED')
    expect(run.instructions?.copyCode).toBe(BOLETO_BARCODE)
    expect(await deps.payments.findPlan(TENANT, 'b1')).toMatchObject({
      round: 1,
    })
  })

  it('runs the ladder as confirmed with the caller as actor', async () => {
    const { rail, deps, retry } = await setup({
      settings: { confirmAboveCents: 1 },
    })
    await retry(TENANT, 'b1', { actor: ACTOR })
    expect(rail.requests).toHaveLength(1)
    const attemptEvent = deps.audit.events.find(
      e => e.action === 'payment.attempt',
    )
    expect(attemptEvent).toMatchObject({
      actor: 'USER',
      actorId: 'session:s1',
      requestId: 'req-1',
    })
  })

  it('records who asked for the retry and in which round', async () => {
    const { deps, retry } = await setup()
    await retry(TENANT, 'b1', { actor: ACTOR })
    const requested = deps.audit.events.filter(
      e => e.action === 'payment.retry_requested',
    )
    expect(requested).toHaveLength(1)
    expect(requested[0]).toMatchObject({
      tenantId: TENANT,
      subjectId: 'b1',
      actor: 'USER',
      actorId: 'session:s1',
      requestId: 'req-1',
      details: { round: 1 },
    })
  })

  it('saves the restarted plan before the bill goes open', async () => {
    const { deps, retry } = await setup()
    const order: string[] = []
    const savePlan = deps.payments.savePlan.bind(deps.payments)
    const saveBill = deps.bills.save.bind(deps.bills)
    deps.payments.savePlan = async (tenantId, plan) => {
      order.push(`plan:${plan.round}`)
      await savePlan(tenantId, plan)
    }
    deps.bills.save = async next => {
      order.push(`bill:${next.status}`)
      await saveBill(next)
    }
    await retry(TENANT, 'b1', { actor: ACTOR })
    expect(order.indexOf('plan:1')).toBeGreaterThanOrEqual(0)
    expect(order.indexOf('plan:1')).toBeLessThan(order.indexOf('bill:OPEN'))
  })

  it('throws not found for an unknown bill', async () => {
    const { retry } = await setup()
    await expect(
      retry(TENANT, 'nope', { actor: ACTOR }),
    ).rejects.toBeInstanceOf(NotFoundError)
  })

  it('counts the new round once and the old failed rows as zero', async () => {
    const { deps, retry } = await setup()
    expect(await deps.payments.committedCents(TENANT, 'pj', TODAY)).toBe(0)
    await retry(TENANT, 'b1', { actor: ACTOR })
    expect(await deps.payments.committedCents(TENANT, 'pj', TODAY)).toBe(12345)
  })
})

describe('retryPayment refusals', () => {
  const cases: Array<[string, Seed]> = [
    ['NOT_ASSISTED', { seed: bill({ status: 'OPEN' }) }],
    [
      'COMMITTED',
      {
        attempts: [
          attempt(),
          attempt({ id: 'p', outcome: 'PAID', externalId: 'x' }),
        ],
      },
    ],
    [
      'OUTCOME_UNKNOWN',
      {
        attempts: [
          attempt(),
          attempt({
            id: 'u',
            outcome: 'FAILED',
            reason: 'IN_FLIGHT_UNRESOLVED',
          }),
        ],
      },
    ],
    [
      'OUTCOME_UNKNOWN',
      {
        attempts: [
          attempt(),
          attempt({ id: 'u', outcome: 'FAILED', reason: 'APPROVAL_EXPIRED' }),
        ],
      },
    ],
    ['NO_AUTOMATIC_STEP', { steps: [ASSISTED_STEP] }],
    ['KILL_SWITCH', { settings: { killSwitch: true } }],
  ]

  it.each(cases)(
    'refuses with %s, calls no rail and changes nothing',
    async (reason, seed) => {
      const { deps, rail, plan, retry } = await setup(seed)
      const before = await deps.bills.findById(TENANT, 'b1')
      const failure = await retry(TENANT, 'b1', { actor: ACTOR }).catch(
        error => error,
      )
      expect(failure).toBeInstanceOf(RetryRefusedError)
      expect(failure).toBeInstanceOf(ConflictError)
      expect((failure as RetryRefusedError).reason).toBe(reason)
      expect(rail.requests).toHaveLength(0)
      expect(await deps.bills.findById(TENANT, 'b1')).toEqual(before)
      expect(await deps.payments.findPlan(TENANT, 'b1')).toEqual(plan)
      expect(
        deps.audit.events.filter(e => e.action === 'payment.retry_requested'),
      ).toEqual([])
    },
  )
})

describe('retryPayment concurrency', () => {
  it('makes at most one rail call for two retries of the same bill', async () => {
    const { rail, retry } = await setup()
    await Promise.allSettled([
      retry(TENANT, 'b1', { actor: ACTOR }),
      retry(TENANT, 'b1', { actor: ACTOR }),
    ])
    expect(rail.requests).toHaveLength(1)
    expect(rail.requests[0]?.idempotencyKey).toBe('b1:r1:0:BOLETO')
  })
})
