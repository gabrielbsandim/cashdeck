import { describe, expect, it } from 'vitest'
import { createBill, Money } from '@cashdeck/domain'
import { FakePaymentRail } from '@/testing/providers'
import { NOW, scenario, TENANT } from '@/testing/scenario.test-helpers'
import { makeRunDuePayments } from '@/use-cases/run-due-payments'
import { makeRunPaymentLadder, payeeKey } from '@/use-cases/run-payment-ladder'

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
      await deps.payees.remember(TENANT, 'pf', payeeKey(bill))
    }
    await deps.bills.save({
      ...(await deps.bills.findById(TENANT, 'b0'))!,
      status: 'PAID',
    })
    const run = makeRunDuePayments({
      ...deps,
      runLadder: makeRunPaymentLadder(deps),
    })
    const summary = await run(TENANT)
    expect(summary).toEqual({ checked: 2, byStatus: { PAID: 2 } })
    expect((await deps.bills.findById(TENANT, 'b3'))?.status).toBe('OPEN')
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
    })(TENANT)
    expect(summary.checked).toBe(101)
    expect(summary.byStatus).toEqual({ ASSISTED: 101 })
  })
})
