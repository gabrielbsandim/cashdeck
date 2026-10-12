import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import {
  makeIncomeSources,
  makeSetSpendingPlan,
} from '@/use-cases/spending-plan'

const CLIENT = '12345678000195'
const MEI = '11222333000181'

async function seed() {
  const deps = fullDeps()
  await deps.accounts.save(account({ id: 'chk', entityId: 'pf' }))
  await deps.accounts.save(
    account({ id: 'card', entityId: 'pf', type: 'CREDIT_CARD' }),
  )
  const credits = [
    { id: 'c1', on: '2026-08-10', cents: 500000, by: CLIENT, name: 'Old Name' },
    {
      id: 'c2',
      on: '2026-09-10',
      cents: 600000,
      by: CLIENT,
      name: 'Client Co',
    },
    { id: 'm1', on: '2026-09-05', cents: 70000, by: '11.222.333/0001-81' },
    { id: 'own', on: '2026-09-06', cents: 90000, by: '52998224725' },
    { id: 'anon', on: '2026-09-07', cents: 1000, by: null },
    { id: 'refund', on: '2026-09-08', cents: 2000, by: MEI, card: true },
  ]
  for (const row of credits) {
    await deps.transactions.save(
      transaction({
        id: row.id,
        accountId: row.card ? 'card' : 'chk',
        bookedOn: row.on,
        amount: Money.of(row.cents),
        description: `Pix ${row.id}`,
        merchant: row.name ?? null,
        counterparty: row.by,
      }),
    )
  }
  for (let index = 0; index < 12; index += 1) {
    await deps.transactions.save(
      transaction({
        id: `small-${index}`,
        accountId: 'chk',
        bookedOn: '2026-10-01',
        amount: Money.of(100 + index),
        counterparty: String(10000000000 + index),
      }),
    )
  }
  return deps
}

describe('spending plan', () => {
  it('lists the payers by what they sent, the chosen ones always', async () => {
    const deps = await seed()
    await makeSetSpendingPlan(deps)(TENANT, {
      incomeSources: [{ taxId: '10000000000', name: 'Smallest' }],
    })
    const { items } = await makeIncomeSources(deps)(TENANT)
    expect(items.slice(0, 2)).toEqual([
      {
        taxId: CLIENT,
        name: 'Client Co',
        total: { cents: 1100000, currency: 'BRL' },
        months: 2,
        lastOn: '2026-09-10',
        selected: false,
      },
      {
        taxId: MEI,
        name: 'Pix m1',
        total: { cents: 70000, currency: 'BRL' },
        months: 1,
        lastOn: '2026-09-05',
        selected: false,
      },
    ])
    expect(items).toHaveLength(13)
    expect(items.at(-1)).toMatchObject({ taxId: '10000000000', selected: true })
    expect(items.map(item => item.taxId)).not.toContain('52998224725')
  })

  it('changes only what the input names', async () => {
    const deps = fullDeps()
    const set = makeSetSpendingPlan(deps)
    const savings = { cents: 100000, currency: 'BRL' as const }
    const sources = [{ taxId: CLIENT, name: 'Client Co' }]
    await set(TENANT, { savings })
    expect(await set(TENANT, { incomeSources: sources })).toEqual({
      savings,
      incomeSources: sources,
    })
    expect(await set(TENANT, { savings: null })).toEqual({
      savings: null,
      incomeSources: sources,
    })
  })
})
