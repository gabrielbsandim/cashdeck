import { describe, expect, it } from 'vitest'
import {
  createBill,
  createPaymentPlan,
  Money,
  type Bill,
} from '@cashdeck/domain'
import { NotFoundError, ProviderNotConfiguredError } from '@/errors/errors'
import { FakePaymentRail } from '@/testing/providers'
import {
  BOLETO_BARCODE,
  NOW,
  PIX_NO_AMOUNT,
  scenario,
  TENANT,
} from '@/testing/scenario.test-helpers'
import { makeBuildPaymentPlan } from '@/use-cases/build-payment-plan'
import { makeRunPaymentLadder, payeeKey } from '@/use-cases/run-payment-ladder'

function bill(overrides: Partial<Bill> = {}): Bill {
  return {
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
  }
}

async function setup(
  rails: FakePaymentRail[],
  settings: Parameters<typeof scenario>[1] = {},
  seed: Bill = bill(),
) {
  const deps = scenario(rails, settings)
  await deps.bills.save(seed)
  await deps.payees.remember(TENANT, seed.entityId, payeeKey(seed))
  return { deps, run: makeRunPaymentLadder(deps) }
}

describe('runPaymentLadder', () => {
  it('pays automatically on the first step', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([
      inter,
      new FakePaymentRail('C6_EMPRESAS'),
    ])
    const result = await run(TENANT, 'b1')
    expect(result.bill).toMatchObject({ status: 'PAID', paidBy: 'RAIL' })
    expect(result.attempts.map(a => a.outcome)).toEqual(['PAID'])
    expect(result.plan.steps.map(s => s.rail)).toEqual([
      'INTER_EMPRESAS',
      'C6_EMPRESAS',
      'ASSISTED',
    ])
    expect(inter.requests[0]?.idempotencyKey).toBe('b1:0:BOLETO')
    expect(deps.audit.events.map(e => e.action)).toEqual(['payment.attempt'])
    expect(result.instructions).toBeNull()
  })

  it('replays a stored rail result instead of paying twice', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter])
    await deps.idempotency.save(TENANT, 'b1:0:BOLETO', 'payment', {
      outcome: 'PAID',
      externalId: 'earlier',
    })
    const result = await run(TENANT, 'b1')
    expect(inter.requests).toHaveLength(0)
    expect(result.attempts[0]).toMatchObject({
      outcome: 'PAID',
      externalId: 'earlier',
    })
  })

  it('moves down to bank approval when the automatic rail is not configured', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS').willReturn(
      new ProviderNotConfiguredError('Inter'),
    )
    const c6 = new FakePaymentRail('C6_EMPRESAS').willReturn({
      outcome: 'PENDING_APPROVAL',
      externalId: 'batch-1',
    })
    const { deps, run } = await setup([inter, c6])
    const result = await run(TENANT, 'b1')
    expect(result.bill.status).toBe('AWAITING_BANK_APPROVAL')
    expect(result.attempts.map(a => [a.rail, a.outcome, a.reason])).toEqual([
      ['INTER_EMPRESAS', 'FAILED', 'NOT_CONFIGURED'],
      ['C6_EMPRESAS', 'PENDING_APPROVAL', null],
    ])
    expect(result.attempts[1]?.externalId).toBe('batch-1')
    expect((await deps.payments.findPlan(TENANT, 'b1'))?.currentStep).toBe(1)
    const again = await run(TENANT, 'b1')
    expect(again.attempts).toEqual([])
  })

  it('ends at the assisted step with instructions when every rail fails', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS').willReturn({
      outcome: 'FAILED',
      reason: 'INSUFFICIENT_FUNDS',
    })
    const c6 = new FakePaymentRail('C6_EMPRESAS').willReturn(new Error('boom'))
    const { run } = await setup([inter, c6])
    const result = await run(TENANT, 'b1')
    expect(result.bill.status).toBe('ASSISTED')
    expect(result.attempts.map(a => a.reason)).toEqual([
      'INSUFFICIENT_FUNDS',
      'boom',
      null,
    ])
    expect(result.instructions).toEqual({
      kind: 'BOLETO',
      copyCode: BOLETO_BARCODE,
      pixCode: null,
      amountCents: 12345,
      dueDate: '2026-10-20',
    })
  })

  it('records an unknown failure for a non error throw', async () => {
    const odd = new FakePaymentRail('INTER_EMPRESAS')
    odd.pay = async () => {
      throw 'nope'
    }
    const { run } = await setup([odd])
    const result = await run(TENANT, 'b1')
    expect(result.attempts[0]?.reason).toBe('UNKNOWN_ERROR')
  })

  it('reports a rail missing from the registry', async () => {
    const { deps, run } = await setup([])
    await deps.payments.savePlan(
      TENANT,
      createPaymentPlan('b1', [
        { mode: 'AUTOMATIC', rail: 'INTER_EMPRESAS', method: 'BOLETO' },
        { mode: 'ASSISTED', rail: 'ASSISTED', method: 'BOLETO' },
      ]),
    )
    const result = await run(TENANT, 'b1')
    expect(result.attempts[0]?.reason).toBe('RAIL_UNAVAILABLE')
  })

  it('respects the daily cap per rail', async () => {
    const capped = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      dailyCapCents: { INTER_EMPRESAS: 1000 },
    })
    const blocked = await capped.run(TENANT, 'b1')
    expect(blocked.attempts[0]?.reason).toBe('DAILY_CAP_EXCEEDED')

    const roomy = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      dailyCapCents: { INTER_EMPRESAS: 1_000_000 },
    })
    expect((await roomy.run(TENANT, 'b1')).bill.status).toBe('PAID')
  })

  it('reports a submitted payment as processing', async () => {
    const { run } = await setup([
      new FakePaymentRail('INTER_EMPRESAS').willReturn({
        outcome: 'SUBMITTED',
      }),
    ])
    expect((await run(TENANT, 'b1')).bill.status).toBe('PROCESSING')
  })

  it('goes straight to assisted when the kill switch is on', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter], { killSwitch: true })
    await deps.payees.remember(TENANT, 'pj', 'nobody')
    const fresh = bill({ id: 'b2', payee: 'Unknown' })
    await deps.bills.save(fresh)
    const result = await run(TENANT, 'b2')
    expect(result.bill.status).toBe('ASSISTED')
    expect(inter.requests).toEqual([])
  })

  it('asks for confirmation for a new payee, then remembers it', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter])
    await deps.bills.save(bill({ id: 'b2', payee: 'New supplier' }))
    const pending = await run(TENANT, 'b2')
    expect(pending.bill.status).toBe('NEEDS_CONFIRMATION')
    expect(deps.audit.events.at(-1)?.action).toBe(
      'payment.confirmation_requested',
    )
    expect((await run(TENANT, 'b2')).bill.status).toBe('NEEDS_CONFIRMATION')

    const confirmed = await run(TENANT, 'b2', { confirmed: true })
    expect(confirmed.bill.status).toBe('PAID')
    expect(await deps.payees.isKnown(TENANT, 'pj', 'New supplier')).toBe(true)
  })

  it('asks for confirmation above the amount threshold', async () => {
    const { run } = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      confirmAboveCents: 10_000,
    })
    expect((await run(TENANT, 'b1')).bill.status).toBe('NEEDS_CONFIRMATION')
    const below = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      confirmAboveCents: 50_000,
    })
    expect((await below.run(TENANT, 'b1')).bill.status).toBe('PAID')
  })

  it('leaves settled and in flight bills alone', async () => {
    const paid = await setup([], {}, bill({ status: 'PAID' }))
    expect((await paid.run(TENANT, 'b1')).attempts).toEqual([])
    const processing = await setup([], {}, bill({ status: 'PROCESSING' }))
    expect((await processing.run(TENANT, 'b1')).bill.status).toBe('PROCESSING')
  })

  it('pays a boleto com Pix through Pix first', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { run } = await setup([inter], {}, bill({ pixCode: PIX_NO_AMOUNT }))
    const result = await run(TENANT, 'b1')
    expect(result.bill.status).toBe('PAID')
    expect(result.attempts.map(a => [a.method, a.outcome])).toEqual([
      ['PIX', 'PAID'],
    ])
    expect(inter.requests[0]).toMatchObject({
      method: 'PIX',
      idempotencyKey: 'b1:0:PIX',
    })
  })

  it('falls back to the barcode, then to assisted with Pix first', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS').willReturn(
      { outcome: 'FAILED', reason: 'PIX_REJECTED' },
      { outcome: 'FAILED', reason: 'BOLETO_REJECTED' },
    )
    const { run } = await setup([inter], {}, bill({ pixCode: PIX_NO_AMOUNT }))
    const result = await run(TENANT, 'b1')
    expect(result.attempts.map(a => [a.method, a.outcome])).toEqual([
      ['PIX', 'FAILED'],
      ['BOLETO', 'FAILED'],
      ['PIX', 'ASSISTED'],
    ])
    expect(inter.requests.map(r => r.idempotencyKey)).toEqual([
      'b1:0:PIX',
      'b1:1:BOLETO',
    ])
    expect(result.instructions).toMatchObject({
      pixCode: PIX_NO_AMOUNT,
      copyCode: BOLETO_BARCODE,
    })
  })

  it('never pays the barcode after a pending Pix attempt', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS').willReturn({
      outcome: 'SUBMITTED',
    })
    const { deps, run } = await setup(
      [inter],
      {},
      bill({ pixCode: PIX_NO_AMOUNT }),
    )
    expect((await run(TENANT, 'b1')).bill.status).toBe('PROCESSING')
    await deps.bills.save(bill({ pixCode: PIX_NO_AMOUNT, status: 'OPEN' }))
    const again = await run(TENANT, 'b1')
    expect(again.attempts).toEqual([])
    expect(inter.requests).toHaveLength(1)
  })

  it('fails loudly for an unknown bill or entity', async () => {
    const { deps, run } = await setup([])
    await expect(run(TENANT, 'missing')).rejects.toThrow(NotFoundError)
    await deps.bills.save(bill({ id: 'b3', entityId: 'ghost' }))
    await expect(run(TENANT, 'b3')).rejects.toThrow('Entity was not found.')
    await expect(
      makeBuildPaymentPlan(deps)(TENANT, bill({ entityId: 'ghost' })),
    ).rejects.toThrow(NotFoundError)
  })
})

describe('payeeKey', () => {
  it('prefers the payee, then the code, then the bill id', () => {
    expect(payeeKey(bill())).toBe('Supplier')
    expect(payeeKey(bill({ payee: null }))).toBe(BOLETO_BARCODE)
    expect(payeeKey(bill({ payee: null, code: null }))).toBe('b1')
  })
})
