import { describe, expect, it } from 'vitest'
import { createTransaction } from '@/entities/transaction'
import {
  billPayment,
  type BillCycle,
  chargesIn,
  cycleHolds,
  cyclesAfter,
  projectInstallments,
} from '@/insights/card-cycles'
import { type InstallmentPlan } from '@/insights/installments'
import { Money } from '@/money/money'

const posted = (id: string, bookedOn: string, cents: number) =>
  createTransaction({
    id,
    tenantId: 't1',
    accountId: 'card',
    amount: Money.of(cents),
    bookedOn,
    description: 'LOJA EXEMPLO',
  })

const plan = (
  key: string,
  lastBilledOn: string,
  number: number,
  count: number,
): InstallmentPlan => ({
  key,
  accountId: 'card',
  name: `Loja ${key}`,
  categoryId: key === 'a' ? 'shopping' : null,
  number,
  count,
  amount: Money.of(5_000),
  purchaseOn: null,
  lastBilledOn,
  transactionIds: [],
})

const september: BillCycle = {
  from: '2026-08-10',
  closesOn: '2026-09-09',
  dueOn: '2026-09-15',
}

describe('card cycles', () => {
  it('repeats the closing and due days in the months after a cycle', () => {
    expect(cyclesAfter(september, 2)).toEqual([
      { from: '2026-09-10', closesOn: '2026-10-09', dueOn: '2026-10-15' },
      { from: '2026-10-10', closesOn: '2026-11-09', dueOn: '2026-11-15' },
    ])
    const endOfMonth = {
      from: '2026-01-01',
      closesOn: '2026-01-31',
      dueOn: '2026-02-07',
    }
    expect(cyclesAfter(endOfMonth, 2)).toEqual([
      { from: '2026-02-01', closesOn: '2026-02-28', dueOn: '2026-03-07' },
      { from: '2026-03-01', closesOn: '2026-03-31', dueOn: '2026-04-07' },
    ])
  })

  it('tells which cycle holds a day', () => {
    expect(cycleHolds(september, '2026-08-10')).toBe(true)
    expect(cycleHolds(september, '2026-09-09')).toBe(true)
    expect(cycleHolds(september, '2026-09-10')).toBe(false)
    expect(cycleHolds(september, '2026-08-09')).toBe(false)
  })

  it('adds up the charges booked inside a cycle', () => {
    const total = chargesIn(september, [
      posted('in', '2026-08-20', -3_000),
      posted('edge', '2026-09-09', -2_000),
      posted('refund', '2026-08-25', 1_000),
      posted('after', '2026-09-10', -9_000),
    ])
    expect(total.cents).toBe(5_000)
  })

  it('puts each installment still to come on the bills after its latest one', () => {
    const cycles = [september, ...cyclesAfter(september, 3)]
    const projected = projectInstallments(
      [
        plan('a', '2026-08-15', 2, 4),
        plan('b', '2026-08-20', 5, 10),
        plan('done', '2026-09-01', 3, 3),
        plan('old', '2026-06-15', 1, 6),
      ],
      cycles,
    )
    expect(projected.map(items => items.map(item => item.key))).toEqual([
      [],
      ['a', 'b'],
      ['a', 'b'],
      ['b'],
    ])
    expect(projected[1]).toEqual([
      {
        key: 'a',
        name: 'Loja a',
        categoryId: 'shopping',
        number: 3,
        count: 4,
        amount: Money.of(5_000),
      },
      expect.objectContaining({ key: 'b', number: 6, categoryId: null }),
    ])
  })

  it('finds the payment that covers a bill', () => {
    const total = Money.of(10_000)
    const payments = [
      posted('early', '2026-09-04', 4_000),
      posted('late', '2026-09-25', 6_000),
      posted('charge', '2026-09-05', -50_000),
    ]
    expect(billPayment(september, total, payments, '2026-09-30')).toBe('PAID')
    const partial = payments.slice(0, 1)
    expect(billPayment(september, total, partial, '2026-09-15')).toBe('DUE')
    expect(billPayment(september, total, partial, '2026-09-16')).toBe(
      'UNCONFIRMED',
    )
    const outside = [
      posted('before', '2026-09-03', 10_000),
      posted('after', '2026-09-26', 10_000),
    ]
    expect(billPayment(september, total, outside, '2026-10-01')).toBe(
      'UNCONFIRMED',
    )
    expect(billPayment(september, Money.of(0), [], '2026-10-01')).toBe('PAID')
  })
})
