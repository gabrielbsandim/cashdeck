import {
  type CreditLine,
  type LocalDate,
  Money,
  ValidationError,
} from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeGetCardTimeline } from '@/use-cases/card-timeline'

const cents = (value: number) => ({ cents: value, currency: 'BRL' })

const credit = (
  closesOn: LocalDate | null,
  dueOn: LocalDate | null,
  openBill: number | null,
): CreditLine => ({
  limit: Money.of(500_000),
  available: Money.of(300_000),
  closesOn,
  dueOn,
  brand: null,
  openBill: openBill === null ? null : Money.of(openBill),
})

const card = (id: string, line: CreditLine | null) =>
  account({
    id,
    entityId: 'pf',
    name: `Cartao ${id}`,
    type: 'CREDIT_CARD',
    balance: Money.of(-90_000),
    numberSuffix: '4821',
    credit: line,
  })

const stored = (
  accountId: string,
  dueOn: LocalDate,
  closesOn: LocalDate,
  total: number,
) => ({
  id: `${accountId}-${dueOn}`,
  tenantId: TENANT,
  accountId,
  externalId: null,
  closesOn,
  dueOn,
  total: Money.of(total),
  minimum: Money.of(total / 10),
})

const installment = (
  id: string,
  bookedOn: LocalDate,
  number: number,
  count: number,
) =>
  transaction({
    id,
    accountId: 'card',
    bookedOn,
    amount: Money.of(-10_000),
    description: `LOJA ${count} PARC ${number}/${count}`,
    categoryId: 'shopping',
    installment: { number, count, purchaseOn: `2026-0${count}-01` },
  })

describe('card timeline', () => {
  it('lays out past, open and forecast bills around the open one', async () => {
    const deps = fullDeps()
    await deps.accounts.save(card('card', credit(null, '2026-09-15', 60_000)))
    await deps.cardBills.saveAll([
      stored('card', '2026-08-15', '2026-08-09', 50_000),
      stored('card', '2026-09-15', '2026-09-09', 70_000),
    ])
    for (const item of [
      transaction({
        id: 'payment',
        accountId: 'card',
        bookedOn: '2026-09-10',
        amount: Money.of(70_000),
      }),
      installment('six', '2026-09-15', 3, 6),
      installment('two', '2026-09-15', 2, 2),
      transaction({ id: 'ahead', accountId: 'card', bookedOn: '2026-10-20' }),
    ]) {
      await deps.transactions.save(item)
    }

    const view = await makeGetCardTimeline(deps)(TENANT, 'card')

    const planned = (number: number) => ({
      key: expect.any(String),
      name: 'LOJA 6',
      categoryId: 'shopping',
      number,
      count: 6,
      amount: cents(10_000),
    })
    expect(view).toEqual({
      accountId: 'card',
      name: 'Cartao card',
      suffix: '4821',
      entityKind: 'PF',
      current: 2,
      bills: [
        {
          closesOn: '2026-08-09',
          dueOn: '2026-08-15',
          total: cents(50_000),
          minimum: cents(5_000),
          state: 'PAST',
          payment: 'UNCONFIRMED',
          range: { from: '2026-07-10', to: '2026-08-09' },
          installments: [],
        },
        {
          closesOn: '2026-09-09',
          dueOn: '2026-09-15',
          total: cents(70_000),
          minimum: cents(7_000),
          state: 'PAST',
          payment: 'PAID',
          range: { from: '2026-08-10', to: '2026-09-09' },
          installments: [],
        },
        {
          closesOn: null,
          dueOn: '2026-10-15',
          total: cents(60_000),
          minimum: null,
          state: 'OPEN',
          payment: null,
          range: { from: '2026-09-10', to: '2026-10-09' },
          installments: [],
        },
        {
          closesOn: '2026-11-09',
          dueOn: '2026-11-15',
          total: cents(15_000),
          minimum: null,
          state: 'FORECAST',
          payment: null,
          range: { from: '2026-10-10', to: '2026-11-09' },
          installments: [planned(4)],
        },
        expect.objectContaining({
          dueOn: '2026-12-15',
          total: cents(10_000),
          installments: [planned(5)],
        }),
        expect.objectContaining({
          dueOn: '2027-01-15',
          state: 'FORECAST',
          installments: [planned(6)],
        }),
      ],
    })
  })

  it('opens the next cycle when the latest bill already closed', async () => {
    const deps = fullDeps()
    await deps.accounts.save(
      card('card', credit('2026-10-03', '2026-10-10', 0)),
    )
    await deps.transactions.save(
      transaction({ id: 'new', accountId: 'card', bookedOn: '2026-10-06' }),
    )

    const view = await makeGetCardTimeline(deps)(TENANT, 'card')

    expect(view.current).toBe(1)
    expect(view.bills).toEqual([
      expect.objectContaining({
        closesOn: '2026-10-03',
        state: 'CLOSED',
        payment: 'PAID',
      }),
      expect.objectContaining({
        closesOn: '2026-11-03',
        dueOn: '2026-11-10',
        total: cents(5_000),
        state: 'OPEN',
        payment: null,
        range: { from: '2026-10-04', to: '2026-11-03' },
      }),
    ])
  })

  it('shows no bills for a card without dates and refuses other accounts', async () => {
    const deps = fullDeps()
    await deps.accounts.save(card('bare', null))
    await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
    const timeline = makeGetCardTimeline(deps)

    expect(await timeline(TENANT, 'bare')).toEqual({
      accountId: 'bare',
      name: 'Cartao bare',
      suffix: '4821',
      entityKind: 'PF',
      bills: [],
      current: null,
    })
    await expect(timeline(TENANT, 'checking')).rejects.toBeInstanceOf(
      ValidationError,
    )
    await expect(timeline(TENANT, 'missing')).rejects.toBeInstanceOf(
      NotFoundError,
    )
  })
})
