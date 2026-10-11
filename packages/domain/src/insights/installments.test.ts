import { describe, expect, it } from 'vitest'
import { createTransaction, type Installment } from '@/entities/transaction'
import {
  committedByMonth,
  finalMonth,
  groupInstallments,
  purchaseName,
  remainingInstallments,
} from '@/insights/installments'
import { Money } from '@/money/money'

function charge(
  id: string,
  options: {
    cents?: number
    bookedOn: string
    installment: Installment | null
    description?: string
    merchant?: string | null
    accountId?: string
  },
) {
  return createTransaction({
    id,
    tenantId: 't1',
    accountId: options.accountId ?? 'card',
    amount: Money.of(options.cents ?? -10_000),
    bookedOn: options.bookedOn,
    description: options.description ?? 'LOJA EXEMPLO PARC 03/10',
    merchant: options.merchant ?? null,
    installment: options.installment,
    categoryId: 'shopping',
  })
}

describe('installments', () => {
  it('strips the counter from a purchase name', () => {
    expect(purchaseName('LOJA EXEMPLO PARC 03/10')).toBe('LOJA EXEMPLO')
    expect(purchaseName('Loja 3 de 12 Centro')).toBe('Loja Centro')
    expect(purchaseName('Parcela 1/2 Curso')).toBe('Curso')
  })

  it('groups the charges of each purchase and keeps the latest one', () => {
    const plans = groupInstallments([
      charge('aug', {
        bookedOn: '2026-08-10',
        installment: { number: 1, count: 3, purchaseOn: '2026-08-01' },
        description: 'LOJA EXEMPLO PARC 01/03',
      }),
      charge('sep', {
        bookedOn: '2026-09-10',
        installment: { number: 2, count: 3, purchaseOn: '2026-08-01' },
        description: 'LOJA EXEMPLO PARC 02/03',
      }),
      charge('course', {
        cents: -5_000,
        bookedOn: '2026-10-05',
        installment: { number: 3, count: 10, purchaseOn: null },
        merchant: 'Curso Exemplo 3/10',
        accountId: 'other-card',
      }),
      charge('refund', {
        cents: 5_000,
        bookedOn: '2026-10-06',
        installment: { number: 1, count: 2, purchaseOn: null },
      }),
      charge('single', { bookedOn: '2026-10-06', installment: null }),
    ])
    expect(plans).toEqual([
      {
        key: 'card|2026-08-01|3|10000',
        accountId: 'card',
        name: 'LOJA EXEMPLO',
        categoryId: 'shopping',
        number: 2,
        count: 3,
        amount: Money.of(10_000),
        purchaseOn: '2026-08-01',
        lastBilledOn: '2026-09-10',
        transactionIds: ['sep', 'aug'],
        missing: [],
      },
      expect.objectContaining({
        key: 'other-card|curso exemplo|10|5000',
        name: 'Curso Exemplo',
        number: 3,
      }),
    ])
    const [store, course] = plans as [
      (typeof plans)[number],
      (typeof plans)[number],
    ]
    expect(remainingInstallments(store)).toBe(1)
    expect(finalMonth(store)).toBe('2026-10')
    expect(finalMonth(course)).toBe('2027-05')
    expect(
      committedByMonth(plans, '2026-10', 3).map(m => [m.month, m.amount.cents]),
    ).toEqual([
      ['2026-10', 10_000],
      ['2026-11', 5_000],
      ['2026-12', 5_000],
    ])
  })

  it('keeps two purchases at the same price apart', () => {
    const plans = groupInstallments(
      ['a1', 'b1', 'a2', 'b2'].map((id, index) =>
        charge(id, {
          bookedOn: index < 2 ? '2026-08-08' : '2026-09-15',
          installment: {
            number: index < 2 ? 1 : 2,
            count: 12,
            purchaseOn: '2026-08-08',
          },
        }),
      ),
    )
    expect(
      plans.map(plan => [plan.key, plan.number, plan.transactionIds]),
    ).toEqual([
      ['card|2026-08-08|12|10000', 2, ['a2', 'a1']],
      ['card|2026-08-08|12|10000|2', 2, ['b2', 'b1']],
    ])
    const [byName] = groupInstallments([
      charge('named', {
        bookedOn: '2026-09-10',
        installment: { number: 3, count: 10, purchaseOn: null },
      }),
    ])
    expect(byName?.key).toBe('card|loja exemplo|10|10000')
  })

  it('counts the installments of a statement the bank never sent', () => {
    const trip = (number: number, bookedOn: string) =>
      charge(`trip-${number}`, {
        bookedOn,
        installment: { number, count: 6, purchaseOn: '2026-02-23' },
        description: 'TRAVEL AGENCY',
      })
    const gym = (number: number, bookedOn: string) =>
      charge(`gym-${number}`, {
        cents: -5_000,
        bookedOn,
        installment: { number, count: 12, purchaseOn: '2026-02-11' },
        description: 'GYM',
      })
    const plans = groupInstallments([
      trip(1, '2026-02-23'),
      trip(4, '2026-05-15'),
      trip(5, '2026-06-15'),
      gym(5, '2026-06-15'),
      gym(7, '2026-08-17'),
      gym(8, '2026-09-15'),
      charge('elsewhere', {
        bookedOn: '2026-12-15',
        installment: { number: 2, count: 3, purchaseOn: null },
        accountId: 'other-card',
      }),
    ])
    const [travel, club] = plans as [
      (typeof plans)[number],
      (typeof plans)[number],
    ]
    expect(travel).toMatchObject({
      number: 6,
      lastBilledOn: '2026-07-15',
      missing: [2, 3, 6],
    })
    expect(remainingInstallments(travel)).toBe(0)
    expect(finalMonth(travel)).toBe('2026-07')
    const [fresh] = groupInstallments([
      charge('fresh', {
        bookedOn: '2026-10-02',
        installment: { number: 1, count: 3, purchaseOn: null },
      }),
    ])
    expect(fresh).toMatchObject({ number: 1, missing: [] })
    const late = groupInstallments([
      charge('late-1', {
        bookedOn: '2026-09-28',
        installment: { number: 1, count: 3, purchaseOn: '2026-09-28' },
        description: 'LATE STORE',
      }),
      charge('running', {
        bookedOn: '2026-10-08',
        installment: { number: 2, count: 3, purchaseOn: null },
      }),
    ])
    expect(late[0]).toMatchObject({
      number: 1,
      lastBilledOn: '2026-09-28',
      missing: [],
    })
    expect(club).toMatchObject({
      number: 8,
      lastBilledOn: '2026-09-15',
      missing: [6],
    })
  })

  it('keeps the day of a shifted statement inside its month', () => {
    const [plan] = groupInstallments([
      charge('last', {
        bookedOn: '2026-01-31',
        installment: { number: 2, count: 4, purchaseOn: null },
      }),
      charge('later', {
        bookedOn: '2026-02-28',
        installment: { number: 3, count: 5, purchaseOn: null },
        description: 'OTHER STORE',
      }),
    ])
    expect(plan).toMatchObject({ number: 3, lastBilledOn: '2026-02-28' })
  })

  it('keeps the rounding cents of one installment in the same plan', () => {
    const plans = groupInstallments(
      [
        ['first', -13_168, 1],
        ['second', -13_166, 2],
        ['other', -13_000, 1],
      ].map(([id, cents, number]) =>
        charge(id as string, {
          cents: cents as number,
          bookedOn: `2026-0${7 + (number as number)}-08`,
          installment: { number: number as number, count: 3, purchaseOn: null },
          description: 'SHOE STORE',
        }),
      ),
    )
    expect(
      plans.map(plan => [plan.key, plan.number, plan.transactionIds]),
    ).toEqual([
      ['card|shoe store|3|13168', 2, ['second', 'first']],
      ['card|shoe store|3|13000', 1, ['other']],
    ])
  })
})
