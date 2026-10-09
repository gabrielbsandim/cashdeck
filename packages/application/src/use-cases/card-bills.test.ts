import { type CreditLine, type LocalDate, Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { account, fullDeps } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeListCardBills } from '@/use-cases/card-bills'

const cents = (value: number) => expect.objectContaining({ cents: value })

const credit = (
  closesOn: LocalDate | null,
  dueOn: LocalDate | null,
): CreditLine => ({
  limit: Money.of(500_000),
  available: Money.of(400_000),
  closesOn,
  dueOn,
  brand: null,
})

const card = (id: string, cents: number, line: CreditLine | null) =>
  account({
    id,
    entityId: 'pf',
    name: `Cartao ${id}`,
    type: 'CREDIT_CARD',
    balance: Money.of(cents),
    numberSuffix: id === 'a' ? '4821' : null,
    credit: line,
  })

const stored = (
  accountId: string,
  dueOn: LocalDate,
  closesOn: LocalDate | null,
  total: number,
) => ({
  id: `${accountId}-${dueOn}`,
  tenantId: TENANT,
  accountId,
  externalId: null,
  closesOn,
  dueOn,
  total: Money.of(total),
  minimum: total > 50_000 ? Money.of(total / 10) : null,
})

describe('card bills', () => {
  it('leads with the open bill and dates the charges of each one', async () => {
    const deps = fullDeps()
    await deps.accounts.save(
      card('a', -15_000, credit('2026-10-12', '2026-10-22')),
    )
    await deps.accounts.save(card('b', 500, null))
    await deps.accounts.save(card('c', -100, credit(null, '2026-10-15')))
    await deps.accounts.save(card('d', 500, credit('2026-10-29', '2026-11-05')))
    await deps.accounts.save(card('e', -100, null))
    await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
    await deps.cardBills.saveAll([
      stored('a', '2026-09-22', '2026-09-12', 90_000),
      stored('a', '2026-08-22', null, 80_000),
      stored('b', '2026-10-10', '2026-10-03', 20_000),
      stored('b', '2026-04-07', '2026-03-31', 10_000),
      stored('c', '2026-10-15', '2026-10-05', 30_000),
      stored('c', '2026-09-15', null, 30_000),
    ])

    const view = await makeListCardBills(deps)(TENANT, 'PF')

    const byId = new Map(view.cards.map(item => [item.accountId, item]))
    expect(view.cards).toHaveLength(5)
    expect(byId.get('a')).toEqual({
      accountId: 'a',
      name: 'Cartao a',
      suffix: '4821',
      entityKind: 'PF',
      bills: [
        {
          closesOn: '2026-10-12',
          dueOn: '2026-10-22',
          total: cents(15_000),
          minimum: null,
          state: 'OPEN',
          range: { from: '2026-09-13', to: '2026-10-12' },
        },
        {
          closesOn: '2026-09-12',
          dueOn: '2026-09-22',
          total: cents(90_000),
          minimum: cents(9_000),
          state: 'PAST',
          range: { from: '2026-08-13', to: '2026-09-12' },
        },
        {
          closesOn: null,
          dueOn: '2026-08-22',
          total: cents(80_000),
          minimum: cents(8_000),
          state: 'PAST',
          range: { from: '2026-07-13', to: '2026-08-12' },
        },
      ],
    })
    expect(byId.get('b')?.bills).toEqual([
      {
        closesOn: null,
        dueOn: '2026-11-10',
        total: cents(0),
        minimum: null,
        state: 'OPEN',
        range: { from: '2026-10-04', to: '2026-11-03' },
      },
      expect.objectContaining({
        state: 'CLOSED',
        range: { from: '2026-04-01', to: '2026-10-03' },
      }),
      expect.objectContaining({
        range: { from: '2026-03-01', to: '2026-03-31' },
      }),
    ])
    expect(byId.get('c')?.bills).toEqual([
      expect.objectContaining({ total: cents(30_000), state: 'CLOSED' }),
      expect.objectContaining({
        dueOn: '2026-09-15',
        state: 'PAST',
        range: { from: '2026-08-06', to: '2026-09-05' },
      }),
    ])
    expect(byId.get('e')?.bills).toEqual([])
    expect(byId.get('d')?.bills).toEqual([
      expect.objectContaining({
        total: cents(0),
        state: 'OPEN',
        range: { from: '2026-09-30', to: '2026-10-29' },
      }),
    ])
  })

  it('answers a scope without cards with no cards', async () => {
    const deps = fullDeps()
    await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
    expect(await makeListCardBills(deps)(TENANT)).toEqual({ cards: [] })
  })
})
