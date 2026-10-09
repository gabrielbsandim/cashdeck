import { describe, expect, it } from 'vitest'
import {
  createBill,
  createPaymentPlan,
  encodeBrCode,
  markBillPaid,
  Money,
  type Bill,
  type PaymentAttempt,
} from '@cashdeck/domain'
import { NotFoundError, ProviderNotConfiguredError } from '@/errors/errors'
import { type RailStatus } from '@/ports/rail-status'
import { FakePaymentRail, FakeReserveFunder } from '@/testing/providers'
import { FakeRailStatusReader } from '@/testing/rail-status'
import {
  BOLETO_BARCODE,
  NOW,
  PIX_NO_AMOUNT,
  scenario,
  TENANT,
  trust,
} from '@/testing/scenario.test-helpers'
import { makeBuildPaymentPlan } from '@/use-cases/build-payment-plan'
import {
  makePrepareFunding,
  makeRunPaymentLadder,
} from '@/use-cases/run-payment-ladder'

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

const personalBill = (overrides: Partial<Bill> = {}) =>
  bill({ entityId: 'pf', ...overrides })

async function setup(
  rails: FakePaymentRail[],
  settings: Parameters<typeof scenario>[1] = {},
  seed: Bill = bill(),
) {
  const deps = scenario(rails, settings)
  await deps.bills.save(seed)
  await trust(deps.payees, seed)
  return { deps, run: makeRunPaymentLadder(deps) }
}

const found = (outcome: RailStatus['outcome'], extra = {}): RailStatus => ({
  outcome,
  externalId: `bill:${outcome}`,
  endToEndId: null,
  settledAt: null,
  ...extra,
})

function inFlight(overrides: Partial<PaymentAttempt> = {}): PaymentAttempt {
  return {
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
  }
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
    expect(deps.audit.events[0]).toMatchObject({
      actor: 'SYSTEM',
      actorId: null,
      requestId: null,
    })
    expect(result.instructions).toBeNull()
  })

  it('writes the in-flight claim before calling the rail', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter])
    let seen: PaymentAttempt[] = []
    inter.pay = async () => {
      seen = await deps.payments.listAttempts(TENANT, 'b1')
      return { outcome: 'PAID', externalId: 'x' }
    }
    await run(TENANT, 'b1')
    expect(seen.map(a => [a.id, a.outcome])).toEqual([
      ['b1:0:BOLETO:claim', 'IN_FLIGHT'],
    ])
    expect(
      (await deps.payments.listAttempts(TENANT, 'b1')).map(a => a.outcome),
    ).toEqual(['IN_FLIGHT', 'PAID'])
  })

  it('replays a stored rail result instead of paying twice', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter], {
      dailyCapCents: { INTER_EMPRESAS: 1 },
    })
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

  it('keeps a call that threw in flight and never sends it again', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS').willReturn(
      new Error('socket hang up'),
    )
    const c6 = new FakePaymentRail('C6_EMPRESAS')
    const { deps, run } = await setup([inter, c6])
    const first = await run(TENANT, 'b1')
    expect(first.bill.status).toBe('PROCESSING')
    expect(first.attempts.map(a => [a.outcome, a.reason])).toEqual([
      ['IN_FLIGHT', 'socket hang up'],
    ])
    expect(await deps.idempotency.find(TENANT, 'b1:0:BOLETO')).toBeNull()
    expect(
      (await deps.payments.listAttempts(TENANT, 'b1')).map(a => a.outcome),
    ).toEqual(['IN_FLIGHT'])

    const again = await run(TENANT, 'b1')
    expect(again.bill.status).toBe('PROCESSING')
    expect(again.attempts).toEqual([])
    expect(inter.requests).toHaveLength(1)
    expect(c6.requests).toHaveLength(0)
    expect(deps.audit.events.at(-1)?.action).toBe('payment.in_flight')
  })

  it('records an unknown throw as in flight too', async () => {
    const odd = new FakePaymentRail('INTER_EMPRESAS')
    odd.pay = async () => {
      throw 'nope'
    }
    const { run } = await setup([odd])
    const result = await run(TENANT, 'b1')
    expect(result.attempts[0]).toMatchObject({
      outcome: 'IN_FLIGHT',
      reason: 'UNKNOWN_ERROR',
    })
  })

  it('resumes a crashed call from the stored rail result', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter])
    await deps.payments.addAttempt(TENANT, inFlight())
    await deps.idempotency.save(TENANT, 'b1:0:BOLETO', 'payment', {
      outcome: 'SUBMITTED',
      externalId: 'stored',
    })
    const result = await run(TENANT, 'b1')
    expect(inter.requests).toHaveLength(0)
    expect(result.bill.status).toBe('PROCESSING')
    expect(result.attempts[0]).toMatchObject({
      idempotencyKey: 'b1:0:BOLETO',
      externalId: 'stored',
    })
  })

  it('asks the rail by idempotency key after a crash, then pays nothing twice', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter])
    const reader = new FakeRailStatusReader('INTER_EMPRESAS').willFind(
      'b1:0:BOLETO',
      found('PAID'),
    )
    deps.railStatus.set('INTER_EMPRESAS', reader)
    await deps.bills.save(bill({ status: 'PROCESSING' }))
    await deps.payments.addAttempt(TENANT, inFlight())
    const result = await makeRunPaymentLadder(deps)(TENANT, 'b1')
    expect(result.bill.status).toBe('PAID')
    expect(reader.lookedUp).toEqual(['b1:0:BOLETO'])
    expect(inter.requests).toHaveLength(0)
    expect(await deps.idempotency.find(TENANT, 'b1:0:BOLETO')).toMatchObject({
      outcome: 'PAID',
    })
    expect((await run(TENANT, 'b1')).attempts).toEqual([])
  })

  it('moves down when the rail says the lost call failed', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const c6 = new FakePaymentRail('C6_EMPRESAS').willReturn({
      outcome: 'PENDING_APPROVAL',
      externalId: 'batch',
    })
    const { deps, run } = await setup([inter, c6])
    deps.railStatus.set(
      'INTER_EMPRESAS',
      new FakeRailStatusReader('INTER_EMPRESAS').willFind(
        'b1:0:BOLETO',
        found('FAILED', { reason: 'REFUSED' }),
      ),
    )
    await deps.payments.addAttempt(TENANT, inFlight())
    const result = await run(TENANT, 'b1')
    expect(result.attempts.map(a => [a.rail, a.outcome])).toEqual([
      ['INTER_EMPRESAS', 'FAILED'],
      ['C6_EMPRESAS', 'PENDING_APPROVAL'],
    ])
    expect(inter.requests).toHaveLength(0)
  })

  it('waits when the rail cannot find or be asked about the lost call', async () => {
    const throwing = new FakeRailStatusReader('INTER_EMPRESAS')
    throwing.findByReference = async () => {
      throw new Error('timeout')
    }
    const silent = new FakeRailStatusReader('INTER_EMPRESAS')
    const blind = {
      id: 'INTER_EMPRESAS' as const,
      status: silent.status.bind(silent),
    }
    for (const reader of [throwing, silent, blind]) {
      const inter = new FakePaymentRail('INTER_EMPRESAS')
      const { deps, run } = await setup([inter])
      deps.railStatus.set('INTER_EMPRESAS', reader)
      await deps.payments.addAttempt(TENANT, inFlight())
      const result = await run(TENANT, 'b1')
      expect(result.bill.status).toBe('PROCESSING')
      expect(inter.requests).toHaveLength(0)
    }
  })

  it('leaves a payment another run holds alone', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter])
    deps.payments.claimAttempt = async () => false
    const result = await run(TENANT, 'b1')
    expect(result.bill.status).toBe('OPEN')
    expect(result.attempts).toEqual([])
    expect(inter.requests).toHaveLength(0)
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
    const c6 = new FakePaymentRail('C6_EMPRESAS').willReturn(
      new ProviderNotConfiguredError('C6'),
    )
    const { run } = await setup([inter, c6])
    const result = await run(TENANT, 'b1')
    expect(result.bill.status).toBe('ASSISTED')
    expect(result.attempts.map(a => a.reason)).toEqual([
      'INSUFFICIENT_FUNDS',
      'NOT_CONFIGURED',
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

  it('respects the daily cap per rail and per entity', async () => {
    const capped = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      dailyCapCents: { INTER_EMPRESAS: 1000 },
    })
    const blocked = await capped.run(TENANT, 'b1')
    expect(blocked.attempts[0]?.reason).toBe('DAILY_CAP_EXCEEDED')

    const roomy = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      dailyCapCents: { INTER_EMPRESAS: 20_000 },
    })
    const other = bill({ id: 'b9', entityId: 'pf' })
    await roomy.deps.bills.save(other)
    await roomy.deps.payments.addAttempt(
      TENANT,
      inFlight({
        id: 'pf-paid',
        billId: 'b9',
        outcome: 'PAID',
        idempotencyKey: 'b9:0:BOLETO',
      }),
    )
    expect((await roomy.run(TENANT, 'b1')).bill.status).toBe('PAID')

    const spent = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      dailyCapCents: { INTER_EMPRESAS: 20_000 },
    })
    await spent.deps.bills.save(bill({ id: 'b8' }))
    await spent.deps.payments.addAttempt(
      TENANT,
      inFlight({ id: 'pj-paid', billId: 'b8', idempotencyKey: 'b8:0:BOLETO' }),
    )
    const full = await spent.run(TENANT, 'b1')
    expect(full.attempts[0]?.reason).toBe('DAILY_CAP_EXCEEDED')
  })

  it('caps one payment and the day of an entity across rails', async () => {
    const single = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      paymentCapCents: 10_000,
    })
    expect((await single.run(TENANT, 'b1')).attempts[0]?.reason).toBe(
      'PAYMENT_CAP_EXCEEDED',
    )

    const daily = await setup([new FakePaymentRail('INTER_EMPRESAS')], {
      entityDailyCapCents: 20_000,
      paymentCapCents: 20_000,
    })
    await daily.deps.bills.save(bill({ id: 'b8' }))
    await daily.deps.payments.addAttempt(
      TENANT,
      inFlight({
        id: 'c6-paid',
        billId: 'b8',
        rail: 'C6_EMPRESAS',
        outcome: 'PENDING_APPROVAL',
        idempotencyKey: 'b8:1:BOLETO',
      }),
    )
    expect((await daily.run(TENANT, 'b1')).attempts[0]?.reason).toBe(
      'ENTITY_DAILY_CAP_EXCEEDED',
    )
  })

  it('lets a bank approval step past the payment and entity caps', async () => {
    const c6 = new FakePaymentRail('C6_EMPRESAS').willReturn({
      outcome: 'PENDING_APPROVAL',
      externalId: 'batch',
    })
    const { run } = await setup([c6], {
      paymentCapCents: 1,
      entityDailyCapCents: 1,
    })
    expect((await run(TENANT, 'b1')).bill.status).toBe('AWAITING_BANK_APPROVAL')
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
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'payment.confirmation_requested',
      details: {
        reasons: ['NEW_PAYEE'],
        recipients: ['boleto:001:NEW SUPPLIER'],
      },
    })
    expect((await run(TENANT, 'b2')).bill.status).toBe('NEEDS_CONFIRMATION')

    const confirmed = await run(TENANT, 'b2', {
      confirmed: true,
      actor: { kind: 'USER', id: 'token:abc', requestId: 'req-1' },
    })
    expect(confirmed.bill.status).toBe('PAID')
    expect(
      await deps.payees.isKnown(TENANT, 'pj', 'boleto:001:NEW SUPPLIER'),
    ).toBe(true)
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'payment.attempt',
      actor: 'USER',
      actorId: 'token:abc',
      requestId: 'req-1',
    })
  })

  it('keys the payee by the Pix key, not by the name on the bill', async () => {
    const known = encodeBrCode({
      key: 'known@example.com',
      merchantName: 'Supplier',
      merchantCity: 'Sao Paulo',
    })
    const swapped = encodeBrCode({
      key: 'someone-else@example.com',
      merchantName: 'Supplier',
      merchantCity: 'Sao Paulo',
    })
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup(
      [inter],
      {},
      bill({ kind: 'PIX_QR', code: known, pixCode: known }),
    )
    await deps.bills.save(
      bill({ id: 'b2', kind: 'PIX_QR', code: swapped, pixCode: swapped }),
    )
    expect((await run(TENANT, 'b2')).bill.status).toBe('NEEDS_CONFIRMATION')
    expect((await run(TENANT, 'b1')).bill.status).toBe('PAID')
  })

  it('asks for a bolepix whose Pix key is new though its beneficiary is known', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter])
    const bolepix = bill({ id: 'b2', pixCode: PIX_NO_AMOUNT })
    await deps.bills.save(bolepix)
    const pending = await run(TENANT, 'b2')
    expect(pending.bill.status).toBe('NEEDS_CONFIRMATION')
    await run(TENANT, 'b2', { confirmed: true })
    expect(
      await deps.payees.isKnown(
        TENANT,
        'pj',
        'pix:123e4567-e12b-12d1-a456-426655440000',
      ),
    ).toBe(true)
  })

  it('asks for confirmation when the amount strays from the paid history', async () => {
    const inter = new FakePaymentRail('INTER_EMPRESAS')
    const { deps, run } = await setup([inter], { maxDeviationPercent: 30 })
    const paid = (overrides: Partial<Bill>, minutesAgo: number) =>
      deps.bills.save(
        markBillPaid(
          bill(overrides),
          'USER',
          new Date(NOW.getTime() - minutesAgo * 60_000),
        ),
      )
    await paid({ id: 'old', amount: Money.of(5000) }, 30)
    await paid({ id: 'unrelated', payee: 'Other', amount: Money.of(9) }, 1)
    expect((await run(TENANT, 'b1')).bill.status).toBe('NEEDS_CONFIRMATION')
    expect(deps.audit.events.at(-1)?.details.reasons).toEqual([
      'AMOUNT_DEVIATION',
    ])
    await paid({ id: 'close', amount: Money.of(12000) }, 20)
    await paid({ id: 'near', amount: Money.of(12500) }, 10)
    await deps.bills.save(bill({ id: 'b3' }))
    expect((await run(TENANT, 'b3')).bill.status).toBe('PAID')
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

  it('leaves settled and waiting bills alone', async () => {
    const paid = await setup([], {}, bill({ status: 'PAID' }))
    expect((await paid.run(TENANT, 'b1')).attempts).toEqual([])
    const processing = await setup([], {}, bill({ status: 'PROCESSING' }))
    expect((await processing.run(TENANT, 'b1')).bill.status).toBe('PROCESSING')
    const assisted = await setup([], {}, bill({ status: 'ASSISTED' }))
    await assisted.deps.payments.addAttempt(TENANT, inFlight())
    expect((await assisted.run(TENANT, 'b1')).bill.status).toBe('ASSISTED')
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

  it('pays a personal Asaas bill only after the reserve is funded', async () => {
    const asaas = new FakePaymentRail('ASAAS')
    const { deps, run } = await setup([asaas], {}, personalBill())
    const result = await run(TENANT, 'b1')
    expect(result.bill.status).toBe('PAID')
    expect(deps.fundings.rows).toMatchObject([
      { billIds: ['b1'], status: 'PAID', amount: Money.of(12345) },
    ])
    expect(deps.audit.events.map(e => e.action)).toEqual([
      'reserve.funding',
      'payment.attempt',
    ])
  })

  it('falls to assisted when the reserve funding fails', async () => {
    const asaas = new FakePaymentRail('ASAAS')
    const deps = scenario([asaas])
    deps.funder = new FakeReserveFunder(0).willReturn({
      outcome: 'FAILED',
      externalId: null,
      reason: 'INSUFFICIENT_FUNDS',
    })
    await deps.bills.save(personalBill())
    await trust(deps.payees, personalBill())
    const result = await makeRunPaymentLadder(deps)(TENANT, 'b1')
    expect(result.bill.status).toBe('ASSISTED')
    expect(result.attempts[0]?.reason).toBe('RESERVE_FUNDING_FAILED')
    expect(asaas.requests).toEqual([])
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

describe('prepareFunding', () => {
  it('funds the personal Asaas bills that would be paid now, in one round', async () => {
    const asaas = new FakePaymentRail('ASAAS')
    const deps = scenario([asaas, new FakePaymentRail('INTER_EMPRESAS')])
    deps.funder = new FakeReserveFunder(2000)
    const ready = [
      personalBill({ id: 'p1', amount: Money.of(5000) }),
      personalBill({ id: 'p2', amount: Money.of(7000) }),
    ]
    const company = bill({ id: 'company' })
    const key = personalBill({
      id: 'key',
      kind: 'PIX_KEY',
      code: 'friend@example.com',
    })
    const sent = personalBill({ id: 'sent' })
    const skipped = [
      personalBill({ id: 'new', payee: 'Stranger' }),
      company,
      personalBill({ id: 'ghost', entityId: 'ghost' }),
      key,
      sent,
    ]
    for (const item of [...ready, ...skipped]) {
      await deps.bills.save(item)
    }
    for (const item of [...ready, company, key, sent]) {
      await trust(deps.payees, item)
    }
    await deps.payments.addAttempt(
      TENANT,
      inFlight({ id: 'sent-1', billId: 'sent', outcome: 'SUBMITTED' }),
    )
    const prepare = makePrepareFunding(deps)
    const summary = await prepare(TENANT, [...ready, ...skipped])
    expect(summary).toEqual({ rounds: 1, fundedCents: 10_000 })
    expect(deps.fundings.rows[0]).toMatchObject({
      billIds: ['p1', 'p2'],
      billsTotal: Money.of(12_000),
      available: Money.of(2000),
      amount: Money.of(10_000),
    })

    const run = makeRunPaymentLadder(deps)
    expect((await run(TENANT, 'p1')).bill.status).toBe('PAID')
    expect(deps.fundings.rows).toHaveLength(1)
  })

  it('skips everything while the kill switch is on', async () => {
    const deps = scenario([new FakePaymentRail('ASAAS')], { killSwitch: true })
    await deps.bills.save(personalBill())
    await trust(deps.payees, personalBill())
    expect(await makePrepareFunding(deps)(TENANT, [personalBill()])).toEqual({
      rounds: 0,
      fundedCents: 0,
    })
  })
})
