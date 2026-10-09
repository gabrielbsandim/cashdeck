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
      },
      expect.objectContaining({
        key: 'card|curso exemplo|10|5000',
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

  it('orders two charges of the same number by date', () => {
    const [plan] = groupInstallments([
      charge('first', {
        bookedOn: '2026-09-10',
        installment: { number: 2, count: 4, purchaseOn: '2026-08-01' },
      }),
      charge('again', {
        bookedOn: '2026-09-12',
        installment: { number: 2, count: 4, purchaseOn: '2026-08-01' },
      }),
    ])
    expect(plan?.transactionIds).toEqual(['again', 'first'])
    const [byName] = groupInstallments([
      charge('named', {
        bookedOn: '2026-09-10',
        installment: { number: 3, count: 10, purchaseOn: null },
      }),
    ])
    expect(byName?.key).toBe('card|loja exemplo|10|10000')
  })
})
