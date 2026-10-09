import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeListInstallments } from '@/use-cases/installments'

const cents = (value: number) => expect.objectContaining({ cents: value })

describe('installments', () => {
  it('lists running plans and what they commit month by month', async () => {
    const deps = fullDeps()
    await deps.accounts.save(
      account({
        id: 'card',
        entityId: 'pf',
        name: 'Cartao Exemplo',
        type: 'CREDIT_CARD',
        numberSuffix: '4321',
      }),
    )
    const charge = (
      id: string,
      bookedOn: string,
      number: number,
      count: number,
      cents: number,
      purchaseOn: string,
      merchant = id.startsWith('tv') ? 'TV Exemplo' : 'Curso Exemplo',
    ) =>
      deps.transactions.save(
        transaction({
          id,
          accountId: 'card',
          bookedOn,
          amount: Money.of(-cents),
          description: `LOJA ${id}`,
          merchant,
          installment: { number, count, purchaseOn },
        }),
      )
    await charge('tv-1', '2026-09-10', 1, 3, 30_000, '2026-09-01')
    await charge('tv-2', '2026-10-05', 2, 3, 30_000, '2026-09-01')
    await charge('course', '2026-10-05', 10, 10, 10_000, '2025-12-20')
    await charge('done', '2026-08-05', 2, 2, 5_000, '2026-07-01')
    await charge('lamp', '2026-10-05', 1, 2, 1_000, '2026-10-01', 'Abajur')
    const view = await makeListInstallments(deps)(TENANT, 'PF')
    expect(view.months).toHaveLength(12)
    expect(view.months.slice(0, 2)).toEqual([
      { month: '2026-11', total: cents(31_000) },
      { month: '2026-12', total: cents(0) },
    ])
    expect(view.plans).toEqual([
      expect.objectContaining({
        name: 'Curso Exemplo',
        number: 10,
        finalMonth: '2026-10',
        remaining: cents(0),
      }),
      expect.objectContaining({ name: 'Abajur', finalMonth: '2026-11' }),
      {
        key: 'card|2026-09-01|3|30000',
        accountId: 'card',
        card: 'Cartao Exemplo',
        cardSuffix: '4321',
        entityKind: 'PF',
        name: 'TV Exemplo',
        categoryId: null,
        number: 2,
        count: 3,
        amount: cents(30_000),
        paid: cents(60_000),
        remaining: cents(30_000),
        total: cents(90_000),
        purchaseOn: '2026-09-01',
        lastBilledOn: '2026-10-05',
        finalMonth: '2026-11',
        transactionIds: ['tv-2', 'tv-1'],
      },
    ])
  })

  it('answers an entity without accounts with an empty list', async () => {
    const view = await makeListInstallments(fullDeps())(TENANT)
    expect(view.plans).toEqual([])
    expect(view.months.every(month => month.total.cents === 0)).toBe(true)
  })
})
