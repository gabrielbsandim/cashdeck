import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { bill, fullDeps } from '@/testing/deps.test-helpers'
import { FakeReserveFunder } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeSetAutoDebit } from '@/use-cases/auto-debit'
import { makeGetBill } from '@/use-cases/bills'
import { makeFundingPlan } from '@/use-cases/funding-plan'

const cents = (value: number) => ({ cents: value, currency: 'BRL' })

describe('funding plan', () => {
  it('averages the personal bills by month and sizes the top-up', async () => {
    const deps = { ...fullDeps(), funder: new FakeReserveFunder(10_000) }
    const bills = [
      bill({ id: 'august', dueDate: '2026-08-10', amount: Money.of(30_000) }),
      bill({
        id: 'paid',
        dueDate: '2026-10-05',
        status: 'PAID',
        amount: Money.of(20_000),
      }),
      bill({ id: 'soon', dueDate: '2026-10-15', amount: Money.of(15_000) }),
      bill({
        id: 'confirm',
        dueDate: '2026-11-02',
        status: 'NEEDS_CONFIRMATION',
        amount: Money.of(5_000),
      }),
      bill({ id: 'far', dueDate: '2026-11-20', amount: Money.of(9_000) }),
      bill({ id: 'gone', dueDate: '2026-10-20', status: 'CANCELLED' }),
      bill({ id: 'company', entityId: 'pj', dueDate: '2026-10-20' }),
      bill({ id: 'debit', dueDate: '2026-10-21', amount: Money.of(7_000) }),
    ]
    for (const item of bills) {
      await deps.bills.save(item)
    }
    await makeSetAutoDebit(deps, makeGetBill(deps))(TENANT, 'debit', true)

    expect(await makeFundingPlan(deps)(TENANT)).toEqual({
      balance: cents(10_000),
      monthlyAverage: cents(21_667),
      months: [
        { month: '2026-08', total: cents(30_000) },
        { month: '2026-09', total: cents(0) },
        { month: '2026-10', total: cents(35_000) },
      ],
      upcoming: cents(20_000),
      topUp: cents(10_000),
    })
  })

  it('keeps six months and no top-up when the balance covers', async () => {
    const deps = { ...fullDeps(), funder: new FakeReserveFunder(50_000) }
    await deps.bills.save(
      bill({ id: 'old', dueDate: '2025-12-10', amount: Money.of(60_000) }),
    )
    await deps.bills.save(
      bill({ id: 'soon', dueDate: '2026-10-15', amount: Money.of(6_000) }),
    )

    const plan = await makeFundingPlan(deps)(TENANT)
    expect(plan.months.map(month => month.month)).toEqual([
      '2026-05',
      '2026-06',
      '2026-07',
      '2026-08',
      '2026-09',
      '2026-10',
    ])
    expect(plan.monthlyAverage).toEqual(cents(1_000))
    expect(plan.topUp).toEqual(cents(0))
  })

  it('shows no balance when Asaas cannot be read', async () => {
    const deps = {
      ...fullDeps(),
      funder: new FakeReserveFunder(new Error('Asaas is not configured.')),
    }
    await deps.bills.save(
      bill({ id: 'soon', dueDate: '2026-10-15', amount: Money.of(6_000) }),
    )

    expect(await makeFundingPlan(deps)(TENANT)).toMatchObject({
      balance: null,
      monthlyAverage: cents(6_000),
      upcoming: cents(6_000),
      topUp: cents(6_000),
    })
  })
})
