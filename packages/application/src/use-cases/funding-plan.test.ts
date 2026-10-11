import { describe, expect, it } from 'vitest'
import { type LocalDate, Money, ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import {
  account,
  bill,
  fullDeps,
  transaction,
} from '@/testing/deps.test-helpers'
import { FakeReserveFunder } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeSetAutoDebit } from '@/use-cases/auto-debit'
import { makeGetBill } from '@/use-cases/bills'
import { makeFundingItems, makeFundingPlan } from '@/use-cases/funding-plan'

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
      expected: cents(20_000),
      pixReserve: cents(0),
      items: [],
      topUp: cents(30_000),
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

  it('adds the bills still to come, the fixed payments and loose Pix', async () => {
    const deps = { ...fullDeps(), funder: new FakeReserveFunder(20_000) }
    const bills = [
      bill({
        id: 'health',
        kind: 'PIX_KEY',
        code: 'cobranca@plano.test',
        payee: 'Plano Saude',
        dueDate: '2026-10-06',
        status: 'PAID',
        amount: Money.of(38_963),
      }),
      bill({
        id: 'health-before',
        kind: 'PIX_KEY',
        code: 'cobranca@plano.test',
        payee: 'Plano Saude',
        dueDate: '2026-09-06',
        status: 'PAID',
        amount: Money.of(38_000),
      }),
      bill({
        id: 'desk',
        payee: 'Internet',
        dueDate: '2026-10-09',
        amount: Money.of(9_999),
      }),
      bill({
        id: 'gone',
        payee: 'Antiga',
        dueDate: '2026-07-20',
        status: 'PAID',
        amount: Money.of(7_000),
      }),
    ]
    for (const item of bills) {
      await deps.bills.save(item)
    }
    await deps.accounts.save(account({ id: 'cash', entityId: 'pf' }))
    await deps.accounts.save(
      account({ id: 'card', entityId: 'pf', type: 'CREDIT_CARD' }),
    )
    const person = '11144477735'
    const sent: Array<[string, LocalDate, number, string | null]> = [
      ['cash', '2026-09-12', -4_000, person],
      ['cash', '2026-09-13', -60_000, person],
      ['cash', '2026-08-03', -2_000, person],
      ['cash', '2026-08-04', -1_000, person],
      ['cash', '2026-07-02', -2_500, person],
      ['cash', '2026-07-03', -3_000, '11222333000181'],
      ['cash', '2026-07-05', 5_000, person],
      ['cash', '2026-06-01', -2_000, person],
      ['cash', '2026-05-01', -1_000, person],
      ['cash', '2026-05-02', -1_500, '52998224725'],
      ['cash', '2026-10-02', -9_000, person],
      ['cash', '2026-09-11', -1_000, null],
      ['card', '2026-09-10', -7_000, person],
    ]
    for (const [index, [accountId, bookedOn, value, counterparty]] of [
      ...sent.entries(),
    ]) {
      await deps.transactions.save(
        transaction({
          id: `pix-${index}`,
          accountId,
          bookedOn,
          amount: Money.of(value),
          counterparty,
        }),
      )
    }
    await deps.transactions.save(
      transaction({
        id: 'moved',
        accountId: 'cash',
        bookedOn: '2026-06-02',
        amount: Money.of(-2_500),
        counterparty: person,
        transferGroupId: 'g',
      }),
    )
    const items = makeFundingItems(deps)
    const condo = await items.add(TENANT, {
      name: 'Condominio',
      amountCents: 55_000,
      dayOfMonth: 10,
    })

    expect(await makeFundingPlan(deps)(TENANT)).toMatchObject({
      upcoming: cents(9_999),
      expected: cents(93_963),
      pixReserve: cents(2_250),
      items: [
        {
          id: condo.id,
          name: 'Condominio',
          amount: cents(55_000),
          dayOfMonth: 10,
        },
      ],
      topUp: cents(86_212),
    })
  })

  it('removes a fixed payment and caps how many there are', async () => {
    const deps = fullDeps()
    const items = makeFundingItems(deps)
    const added = []
    for (let day = 1; day <= 30; day += 1) {
      added.push(
        await items.add(TENANT, {
          name: `Fixa ${day}`,
          amountCents: 1_000,
          dayOfMonth: day,
        }),
      )
    }
    await expect(
      items.add(TENANT, { name: 'Extra', amountCents: 1_000, dayOfMonth: 31 }),
    ).rejects.toBeInstanceOf(ValidationError)
    const first = added[0]?.id as string
    expect(await items.remove(TENANT, first)).toEqual({ id: first })
    await expect(items.remove(TENANT, first)).rejects.toBeInstanceOf(
      NotFoundError,
    )
  })
})
