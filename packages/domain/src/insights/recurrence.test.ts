import { describe, expect, it } from 'vitest'
import { createTransaction } from '@/entities/transaction'
import {
  detectRecurring,
  groupByRecurrence,
  recurrenceKey,
  summarizeCharges,
} from '@/insights/recurrence'
import { Money } from '@/money/money'

const tx = (
  id: string,
  bookedOn: string,
  cents: number,
  description = 'STREAMING EXEMPLO',
  extra: { merchant?: string; installment?: boolean } = {},
) =>
  createTransaction({
    id,
    tenantId: 't1',
    accountId: 'card',
    amount: Money.of(cents),
    bookedOn,
    description,
    merchant: extra.merchant ?? null,
    installment: extra.installment
      ? { number: 1, count: 2, purchaseOn: null }
      : null,
  })

const monthly = (prefix: string, cents: number[], description?: string) =>
  cents.map((value, index) =>
    tx(`${prefix}${index}`, `2026-0${7 + index}-1${index}`, value, description),
  )

describe('recurrence', () => {
  it('keys a charge by its merchant or description words', () => {
    expect(
      recurrenceKey(tx('a', '2026-10-01', -1, 'PIX ENVIADO Academia 123')),
    ).toBe('academia')
    expect(
      recurrenceKey(
        tx('b', '2026-10-01', -1, 'x', { merchant: 'Musica Exemplo' }),
      ),
    ).toBe('musica exemplo')
  })

  it('summarizes the newest charge and the one before', () => {
    const charge = summarizeCharges('streaming exemplo', [
      tx('old', '2026-08-12', -3_990),
      tx('new', '2026-09-15', -4_490),
    ])
    expect(charge).toEqual({
      key: 'streaming exemplo',
      name: 'STREAMING EXEMPLO',
      accountId: 'card',
      categoryId: null,
      amount: Money.of(4_490),
      previousAmount: Money.of(3_990),
      dayOfMonth: 15,
      lastChargeOn: '2026-09-15',
      months: 2,
      transactionIds: ['new', 'old'],
      charges: [
        {
          transactionId: 'new',
          bookedOn: '2026-09-15',
          amount: Money.of(4_490),
        },
        {
          transactionId: 'old',
          bookedOn: '2026-08-12',
          amount: Money.of(3_990),
        },
      ],
    })
    expect(
      summarizeCharges('k', [tx('one', '2026-09-15', -100)]).previousAmount,
    ).toBeNull()
  })

  it('finds steady monthly charges that still run', () => {
    const found = detectRecurring(
      [
        ...monthly('s', [-3_990, -3_990, -4_490]),
        ...monthly('few', [-1_000, -1_000], 'ACADEMIA EXEMPLO'),
        ...monthly('jumpy', [-1_000, -9_000, -1_000], 'MERCADO EXEMPLO'),
        ...monthly('busy', [-500, -500, -500], 'PADARIA EXEMPLO'),
        tx('busy-extra', '2026-09-20', -500, 'PADARIA EXEMPLO'),
        tx('busy-more', '2026-09-21', -500, 'PADARIA EXEMPLO'),
        ...monthly('income', [5_000, 5_000, 5_000], 'SALARIO EXEMPLO'),
        ...monthly('power', [-26_200, -24_100, -27_900], 'ENERGIA EXEMPLO'),
        ...monthly('fx', [-10_120, -10_340, -10_060], 'NUVEM EXEMPLO'),
        tx('split', '2026-09-10', -100, 'PARCELADO EXEMPLO', {
          installment: true,
        }),
        tx('noise', '2026-09-10', -100, 'PIX 12'),
      ],
      '2026-10-08',
    )
    expect(found.map(charge => charge.key)).toEqual([
      'streaming exemplo',
      'nuvem exemplo',
    ])
    expect(
      detectRecurring(monthly('s', [-3_990, -3_990, -3_990]), '2026-12-31'),
    ).toEqual([])
    expect(
      groupByRecurrence([tx('noise', '2026-09-10', -100, 'PIX 12')]).size,
    ).toBe(0)
  })
})
