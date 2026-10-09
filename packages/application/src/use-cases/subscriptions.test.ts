import { Money, ValidationError } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeSubscriptions } from '@/use-cases/subscriptions'

const cents = (value: number) => expect.objectContaining({ cents: value })

async function seeded() {
  const deps = fullDeps()
  await deps.accounts.save(
    account({ id: 'card', entityId: 'pf', type: 'CREDIT_CARD' }),
  )
  await deps.accounts.save(account({ id: 'company', entityId: 'pj' }))
  const lines: Array<[string, string, string, number, string]> = [
    ['music-1', 'card', '2026-07-12', 2_190, 'MUSICA EXEMPLO'],
    ['music-2', 'card', '2026-08-12', 2_190, 'MUSICA EXEMPLO'],
    ['music-3', 'card', '2026-09-12', 2_390, 'MUSICA EXEMPLO'],
    ['gym-1', 'card', '2026-07-02', 9_900, 'ACADEMIA EXEMPLO'],
    ['gym-2', 'card', '2026-08-02', 9_900, 'ACADEMIA EXEMPLO'],
    ['gym-3', 'card', '2026-09-02', 9_900, 'ACADEMIA EXEMPLO'],
    ['gym-4', 'card', '2026-10-02', 9_900, 'ACADEMIA EXEMPLO'],
    ['host-1', 'company', '2026-07-20', 5_000, 'HOSPEDAGEM EXEMPLO'],
    ['host-2', 'company', '2026-08-20', 5_000, 'HOSPEDAGEM EXEMPLO'],
    ['host-3', 'company', '2026-09-20', 5_000, 'HOSPEDAGEM EXEMPLO'],
    ['once', 'card', '2026-09-12', 1_500, 'LIVRARIA EXEMPLO'],
  ]
  for (const [id, accountId, bookedOn, value, description] of lines) {
    await deps.transactions.save(
      transaction({
        id,
        accountId,
        bookedOn,
        amount: Money.of(-value),
        description,
      }),
    )
  }
  return { deps, subscriptions: makeSubscriptions(deps) }
}

describe('subscriptions', () => {
  it('suggests steady charges and lists the confirmed ones', async () => {
    const { subscriptions } = await seeded()
    const before = await subscriptions.list(TENANT)
    expect(before.items).toEqual([])
    expect(before.suggestions.map(s => [s.key, s.entityKind])).toEqual([
      ['academia exemplo', 'PF'],
      ['musica exemplo', 'PF'],
      ['hospedagem exemplo', 'PJ'],
    ])
    const music = before.suggestions[1]
    expect(music).toMatchObject({
      id: null,
      amount: cents(2_390),
      previousAmount: cents(2_190),
      priceChanged: true,
      dayOfMonth: 12,
      thisMonth: 'UPCOMING',
      nextChargeOn: '2026-10-12',
    })
    expect(music?.charges).toEqual([
      {
        transactionId: 'music-3',
        bookedOn: '2026-09-12',
        amount: cents(2_390),
      },
      {
        transactionId: 'music-2',
        bookedOn: '2026-08-12',
        amount: cents(2_190),
      },
      {
        transactionId: 'music-1',
        bookedOn: '2026-07-12',
        amount: cents(2_190),
      },
    ])
    expect(before.suggestions[0]).toMatchObject({
      thisMonth: 'PAID',
      priceChanged: false,
      nextChargeOn: '2026-11-02',
    })
    expect(before.suggestions[2]?.thisMonth).toBe('UPCOMING')

    const { id } = await subscriptions.confirm(TENANT, 'music-3')
    await subscriptions.confirm(TENANT, 'once')
    await subscriptions.dismiss(TENANT, 'gym-4')
    const after = await subscriptions.list(TENANT, 'PF')
    expect(after.items.map(item => [item.name, item.id !== null])).toEqual([
      ['LIVRARIA EXEMPLO', true],
      ['MUSICA EXEMPLO', true],
    ])
    expect(after.items[1]?.id).toBe(id)
    expect(after.items[0]).toMatchObject({
      previousAmount: null,
      priceChanged: false,
      transactionIds: ['once'],
      charges: [
        { transactionId: 'once', bookedOn: '2026-09-12', amount: cents(1_500) },
      ],
    })
    expect(after.suggestions).toEqual([])
    expect(after).toMatchObject({
      monthly: cents(3_890),
      yearly: cents(46_680),
      previousMonth: cents(3_890),
      changePercent: 0,
    })
  })

  it('keeps a confirmed charge that left the history and marks it late', async () => {
    const { deps, subscriptions } = await seeded()
    await deps.recurrences.save({
      id: 'old',
      tenantId: TENANT,
      entityId: 'pf',
      key: 'jornal exemplo',
      name: 'Jornal Exemplo',
      amount: Money.of(1_000),
      dayOfMonth: 1,
      status: 'CONFIRMED',
      lastSeenOn: '2025-01-01',
    })
    await deps.recurrences.save({
      id: 'never',
      tenantId: TENANT,
      entityId: 'pf',
      key: 'revista exemplo',
      name: 'Revista Exemplo',
      amount: Money.of(500),
      dayOfMonth: 20,
      status: 'CONFIRMED',
      lastSeenOn: null,
    })
    await deps.recurrences.save({
      id: 'month-end',
      tenantId: TENANT,
      entityId: 'pf',
      key: 'clube exemplo',
      name: 'Clube Exemplo',
      amount: Money.of(800),
      dayOfMonth: 31,
      status: 'CONFIRMED',
      lastSeenOn: '2026-10-01',
    })
    const view = await subscriptions.list(TENANT, 'PF')
    expect(
      view.items.map(item => [
        item.name,
        item.thisMonth,
        item.nextChargeOn,
        item.charges,
      ]),
    ).toEqual([
      ['Jornal Exemplo', 'LATE', '2026-10-01', []],
      ['Revista Exemplo', 'UPCOMING', '2026-10-20', []],
      ['Clube Exemplo', 'PAID', '2026-11-30', []],
    ])
    expect(await subscriptions.remove(TENANT, 'old')).toEqual({ id: 'old' })
    expect((await deps.recurrences.findById(TENANT, 'old'))?.status).toBe(
      'DISMISSED',
    )
  })

  it('leaves a metered utility bill out of the suggestions', async () => {
    const { deps, subscriptions } = await seeded()
    const bills: Array<[string, number]> = [
      ['2026-07-16', 26_200],
      ['2026-08-18', 31_400],
      ['2026-09-16', 28_900],
    ]
    for (const [bookedOn, value] of bills) {
      await deps.transactions.save(
        transaction({
          id: `power-${bookedOn}`,
          accountId: 'card',
          bookedOn,
          amount: Money.of(-value),
          description: 'ENERGIA EXEMPLO',
        }),
      )
    }
    const view = await subscriptions.list(TENANT, 'PF')
    expect(view.suggestions.map(s => s.key)).not.toContain('energia exemplo')
  })

  it('refuses what cannot recur', async () => {
    const { deps, subscriptions } = await seeded()
    await deps.transactions.save(
      transaction({ id: 'refund', accountId: 'card', amount: Money.of(100) }),
    )
    await deps.transactions.save(
      transaction({ id: 'blank', accountId: 'card', description: 'PIX 12' }),
    )
    await deps.transactions.save(
      transaction({ id: 'orphan', accountId: 'gone' }),
    )
    await expect(subscriptions.confirm(TENANT, 'refund')).rejects.toThrow(
      ValidationError,
    )
    await expect(subscriptions.confirm(TENANT, 'blank')).rejects.toThrow(
      'cannot recur',
    )
    await expect(subscriptions.confirm(TENANT, 'x')).rejects.toThrow(
      NotFoundError,
    )
    await expect(subscriptions.confirm(TENANT, 'orphan')).rejects.toThrow(
      NotFoundError,
    )
    await expect(subscriptions.remove(TENANT, 'x')).rejects.toThrow(
      NotFoundError,
    )
    const empty = await makeSubscriptions(fullDeps()).list(TENANT)
    expect([empty.items, empty.suggestions, empty.changePercent]).toEqual([
      [],
      [],
      null,
    ])
  })
})
