import { describe, expect, it } from 'vitest'
import { createBill, Money } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { FakePaymentRail } from '@/testing/providers'
import { NOW, scenario, TENANT } from '@/testing/scenario.test-helpers'
import {
  makeDescribeBill,
  makeGetBill,
  makeListBills,
  makeMarkBillPaid,
} from '@/use-cases/bills'
import { makeRunPaymentLadder, payeeKey } from '@/use-cases/run-payment-ladder'

function seed(id: string, dueDate: string) {
  return createBill({
    id,
    tenantId: TENANT,
    entityId: 'pf',
    kind: 'PIX_KEY',
    source: 'CHAT',
    payee: 'Friend',
    amount: Money.of(100),
    dueDate,
    code: 'friend@example.com',
    createdAt: NOW,
  })
}

describe('bill queries and manual payment', () => {
  it('returns the bill detail with its plan and attempts', async () => {
    const deps = scenario([new FakePaymentRail('MERCADO_PAGO_PAYOUTS')])
    const target = seed('b1', '2026-10-20')
    await deps.bills.save(target)
    await deps.payees.remember(TENANT, 'pf', payeeKey(target))
    const getBill = makeGetBill(deps)
    expect((await getBill(TENANT, 'b1')).plan).toBeNull()

    await makeRunPaymentLadder(deps)(TENANT, 'b1')
    const detail = await getBill(TENANT, 'b1')
    expect(detail.status).toBe('PAID')
    expect(detail.entityKind).toBe('PF')
    expect(detail.paidAt).toBe(NOW.toISOString())
    expect(detail.plan?.steps.map(s => s.rail)).toEqual([
      'MERCADO_PAGO_PAYOUTS',
      'ASSISTED',
    ])
    expect(detail.attempts[0]).toMatchObject({
      outcome: 'PAID',
      amount: { cents: 100 },
    })
    await expect(getBill(TENANT, 'nope')).rejects.toThrow(NotFoundError)
  })

  it('lists bills by due date with a cursor', async () => {
    const deps = scenario()
    await deps.bills.save(seed('b2', '2026-10-22'))
    await deps.bills.save(seed('b1', '2026-10-21'))
    await deps.bills.save(seed('b3', '2026-10-21'))
    const list = makeListBills(deps)
    const first = await list(TENANT, {}, { limit: 2 })
    expect(first.items.map(b => [b.id, b.entityKind])).toEqual([
      ['b1', 'PF'],
      ['b3', 'PF'],
    ])
    const second = await list(
      TENANT,
      {},
      { limit: 2, cursor: first.nextCursor },
    )
    expect(second.items.map(b => b.id)).toEqual(['b2'])
    expect(second.nextCursor).toBeNull()
    expect(
      (await list(TENANT, { entityId: 'pj' }, { limit: 5 })).items,
    ).toEqual([])
    expect(
      (await list(TENANT, { status: 'OPEN', entityId: 'pf' }, { limit: 5 }))
        .items,
    ).toHaveLength(3)
    expect(
      (await list(TENANT, { status: 'PAID' }, { limit: 5 })).items,
    ).toEqual([])
    expect((await list('other', {}, { limit: 5 })).items).toEqual([])
  })

  it('describes a bill with its entity kind', async () => {
    const deps = scenario()
    const describeBill = makeDescribeBill(deps)
    expect(
      (await describeBill(TENANT, seed('b1', '2026-10-20'))).entityKind,
    ).toBe('PF')
    await expect(
      describeBill(TENANT, { ...seed('b2', '2026-10-20'), entityId: 'gone' }),
    ).rejects.toThrow(NotFoundError)
  })

  it('marks a bill paid by the user once', async () => {
    const deps = scenario()
    await deps.bills.save(seed('b1', '2026-10-20'))
    const markPaid = makeMarkBillPaid(deps)
    const paid = await markPaid(TENANT, 'b1', 'receipt.pdf')
    expect(paid).toMatchObject({ status: 'PAID', paidBy: 'USER' })
    expect(await markPaid(TENANT, 'b1')).toBe(paid)
    expect(deps.audit.events).toHaveLength(1)
    expect(deps.audit.events[0]?.details).toEqual({ proof: 'receipt.pdf' })
    await expect(markPaid(TENANT, 'nope')).rejects.toThrow(NotFoundError)
  })
})
