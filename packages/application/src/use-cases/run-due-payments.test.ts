import { describe, expect, it } from 'vitest'
import { createBill, Money } from '@cashdeck/domain'
import { FakePaymentRail } from '@/testing/providers'
import { NOW, scenario, TENANT, trust } from '@/testing/scenario.test-helpers'
import { makeMarkBillPaid } from '@/use-cases/bills'
import { makeRunDuePayments } from '@/use-cases/run-due-payments'
import {
  makePrepareFunding,
  makeRunPaymentLadder,
} from '@/use-cases/run-payment-ladder'

describe('runDuePayments', () => {
  it('runs the ladder for open bills due by the next business day', async () => {
    const deps = scenario([new FakePaymentRail('MERCADO_PAGO_PAYOUTS')])
    const due = [
      '2026-10-07',
      '2026-10-08',
      '2026-10-09',
      '2026-10-13',
      '2026-10-20',
    ]
    for (const [index, dueDate] of due.entries()) {
      const bill = createBill({
        id: `b${index}`,
        tenantId: TENANT,
        entityId: 'pf',
        kind: 'PIX_KEY',
        source: 'MANUAL',
        payee: 'Friend',
        amount: Money.of(100),
        dueDate,
        code: `key-${index}`,
        createdAt: NOW,
      })
      await deps.bills.save(bill)
      await trust(deps.payees, bill)
    }
    await deps.bills.save({
      ...(await deps.bills.findById(TENANT, 'b0'))!,
      status: 'PAID',
    })
    const run = makeRunDuePayments({
      ...deps,
      runLadder: makeRunPaymentLadder(deps),
      prepareFunding: makePrepareFunding(deps),
    })
    const summary = await run(TENANT)
    expect(summary).toEqual({
      checked: 2,
      byStatus: { PAID: 2 },
      funding: { rounds: 0, fundedCents: 0 },
    })
    expect((await deps.bills.findById(TENANT, 'b3'))?.status).toBe('OPEN')
  })

  it('skips the month paid by hand and pays the next one', async () => {
    const rail = new FakePaymentRail('MERCADO_PAGO_PAYOUTS')
    const deps = scenario([rail])
    for (const [id, dueDate] of [
      ['oct', '2026-10-09'],
      ['nov', '2026-11-09'],
    ] as const) {
      const bill = createBill({
        id,
        tenantId: TENANT,
        entityId: 'pf',
        kind: 'PIX_KEY',
        source: 'GMAIL',
        payee: 'Condo',
        amount: Money.of(50000),
        dueDate,
        code: 'condo@example.com',
        createdAt: NOW,
      })
      await deps.bills.save(bill)
      await trust(deps.payees, bill)
    }
    await makeMarkBillPaid(deps)(TENANT, 'oct', 'paid from another account')
    const runLadder = makeRunPaymentLadder(deps)
    const run = makeRunDuePayments({
      ...deps,
      runLadder,
      prepareFunding: makePrepareFunding(deps),
    })

    expect((await run(TENANT)).checked).toBe(0)
    expect((await runLadder(TENANT, 'oct')).attempts).toEqual([])
    expect(rail.requests).toEqual([])

    deps.clock.set(new Date('2026-11-06T12:00:00Z'))
    expect((await run(TENANT)).byStatus).toEqual({ PAID: 1 })
    expect(rail.requests.map(request => request.bill.id)).toEqual(['nov'])
    expect(await deps.bills.findById(TENANT, 'oct')).toMatchObject({
      status: 'PAID',
      paidBy: 'USER',
    })
    expect((await deps.bills.findById(TENANT, 'nov'))?.paidBy).toBe('RAIL')
  })

  it('walks every page', async () => {
    const deps = scenario()
    for (let index = 0; index < 101; index += 1) {
      await deps.bills.save(
        createBill({
          id: `p${String(index).padStart(3, '0')}`,
          tenantId: TENANT,
          entityId: 'pf',
          kind: 'PIX_KEY',
          source: 'MANUAL',
          amount: Money.of(1),
          dueDate: '2026-10-08',
          code: `k${index}`,
          createdAt: NOW,
        }),
      )
    }
    const summary = await makeRunDuePayments({
      ...deps,
      runLadder: makeRunPaymentLadder(deps),
      prepareFunding: makePrepareFunding(deps),
    })(TENANT)
    expect(summary.checked).toBe(101)
    expect(summary.byStatus).toEqual({ ASSISTED: 101 })
  })

  it('funds the reserve for the day before paying the Asaas bills', async () => {
    const deps = scenario([new FakePaymentRail('ASAAS')])
    for (const [index, cents] of [3000, 4000].entries()) {
      const bill = createBill({
        id: `a${index}`,
        tenantId: TENANT,
        entityId: 'pf',
        kind: 'BOLETO',
        source: 'MANUAL',
        payee: 'Utility',
        amount: Money.of(cents),
        dueDate: '2026-10-09',
        code: '00199160500000123450000002800012345678901217',
        createdAt: NOW,
      })
      await deps.bills.save(bill)
      await trust(deps.payees, bill)
    }
    const summary = await makeRunDuePayments({
      ...deps,
      runLadder: makeRunPaymentLadder(deps),
      prepareFunding: makePrepareFunding(deps),
    })(TENANT)
    expect(summary).toEqual({
      checked: 2,
      byStatus: { PAID: 2 },
      funding: { rounds: 1, fundedCents: 7000 },
    })
    expect(deps.funder.requests).toEqual([
      {
        tenantId: TENANT,
        entityId: 'pf',
        amountCents: 7000,
        idempotencyKey: 'reserve:pf:2026-10-08:1',
        description: 'Cashdeck bills 2026-10-08',
      },
    ])
  })
})
