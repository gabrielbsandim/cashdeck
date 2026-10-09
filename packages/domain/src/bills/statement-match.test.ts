import { describe, expect, it } from 'vitest'
import { createBill } from '@/bills/bill'
import { matchBillsToStatement } from '@/bills/statement-match'
import { createTransaction } from '@/entities/transaction'
import { Money } from '@/money/money'

const bill = (id: string, cents: number, dueDate: string) =>
  createBill({
    id,
    tenantId: 't1',
    entityId: 'e1',
    kind: 'BOLETO',
    source: 'GMAIL',
    amount: Money.of(cents),
    dueDate,
    code: '123',
    createdAt: new Date('2026-10-09T12:00:00Z'),
  })

const tx = (id: string, cents: number, bookedOn: string, currency = 'BRL') =>
  createTransaction({
    id,
    tenantId: 't1',
    accountId: 'a1',
    amount: Money.of(cents, currency),
    bookedOn,
    description: 'pix key transfer',
    externalId: null,
  })

const pairs = (matches: ReturnType<typeof matchBillsToStatement>) =>
  matches.map(m => [m.bill.id, m.transaction.id])

describe('matchBillsToStatement', () => {
  it('pays a bill with the outgoing transaction of the same amount', () => {
    const matches = matchBillsToStatement(
      [bill('amil', 38963, '2026-10-06'), bill('desk', 9999, '2026-10-08')],
      [
        tx('t1', -38963, '2026-10-06'),
        tx('t2', -9999, '2026-10-08'),
        tx('t3', 9999, '2026-10-08'),
      ],
    )
    expect(pairs(matches)).toEqual([
      ['amil', 't1'],
      ['desk', 't2'],
    ])
  })

  it('waits longer for a bank debit to post', () => {
    const debit = bill('claro', 20880, '2026-10-08')
    const late = [tx('late', -20880, '2026-10-22')]
    expect(matchBillsToStatement([debit], late)).toEqual([])
    expect(
      pairs(matchBillsToStatement([debit], late, b => b.id === 'claro')),
    ).toEqual([['claro', 'late']])
  })

  it('keeps to the window around the due date and to the currency', () => {
    const due = bill('b', 1000, '2026-10-20')
    expect(
      pairs(
        matchBillsToStatement(
          [due],
          [
            tx('early', -1000, '2026-10-09'),
            tx('late', -1000, '2026-10-28'),
            tx('usd', -1000, '2026-10-20', 'USD'),
          ],
        ),
      ),
    ).toEqual([])
    expect(
      pairs(matchBillsToStatement([due], [tx('edge', -1000, '2026-10-10')])),
    ).toEqual([['b', 'edge']])
    expect(
      pairs(matchBillsToStatement([due], [tx('edge', -1000, '2026-10-27')])),
    ).toEqual([['b', 'edge']])
  })

  it('uses each transaction once, the closest date first', () => {
    const matches = matchBillsToStatement(
      [bill('sep', 5000, '2026-10-01'), bill('oct', 5000, '2026-10-08')],
      [tx('t1', -5000, '2026-10-07')],
    )
    expect(pairs(matches)).toEqual([['oct', 't1']])
    const both = matchBillsToStatement(
      [bill('a', 5000, '2026-10-08')],
      [tx('t1', -5000, '2026-10-05'), tx('t2', -5000, '2026-10-08')],
    )
    expect(pairs(both)).toEqual([['a', 't2']])
  })
})
