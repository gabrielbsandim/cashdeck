import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { Money } from '@cashdeck/domain'
import { getContainer, resetContainer } from '@/server/container'
import { GET as listInvestments } from '@/app/api/v1/investments/route'

const TOKEN = 'test-token-0123456789'
const TENANT = 'local'

function get(query = '') {
  return new Request(`http://localhost/api/v1/investments${query}`, {
    headers: { authorization: `Bearer ${TOKEN}` },
  })
}

async function json(response: Response) {
  return { status: response.status, body: await response.json() }
}

beforeEach(() => {
  vi.stubEnv('CASHDECK_API_TOKEN', TOKEN)
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

describe('investments route', () => {
  it('sums the positions held and filters by entity', async () => {
    const { deps } = getContainer()
    const personal = await deps.entities.findByKind(TENANT, 'PF')
    const bank = await deps.institutions.ensure({
      id: 'bank',
      tenantId: TENANT,
      name: 'Banco Exemplo',
      manual: false,
    })
    await deps.investments.saveAll([
      {
        id: 'inv1',
        tenantId: TENANT,
        entityId: personal?.id ?? '',
        connectionId: 'conn1',
        institutionId: bank.id,
        externalId: 'ext1',
        name: 'CDB Banco Exemplo',
        kind: 'FIXED_INCOME',
        subtype: 'CDB',
        issuer: 'BANCO EXEMPLO S.A.',
        status: 'ACTIVE',
        balance: Money.of(105_000),
        invested: Money.of(100_000),
        profit: null,
        quantity: 1,
        rate: { percent: 102, index: 'CDI', fixedAnnual: null },
        lastMonthRate: null,
        lastTwelveMonthsRate: null,
        dueOn: '2028-04-04',
        valuedOn: '2026-10-07',
        syncedAt: new Date('2026-10-08T12:00:00.000Z'),
      },
    ])

    const all = await json(await listInvestments(get()))
    expect(all.status).toBe(200)
    expect(all.body.data).toMatchObject({
      total: { cents: 105_000, currency: 'BRL' },
      profit: { cents: 5_000 },
      institutions: [{ institution: 'Banco Exemplo', count: 1 }],
      kinds: [{ kind: 'FIXED_INCOME', count: 1 }],
      positions: [{ id: 'inv1', profitPercent: 5, dueOn: '2028-04-04' }],
    })

    const company = await json(await listInvestments(get('?entity=PJ')))
    expect(company.body.data.positions).toEqual([])

    const invalid = await listInvestments(get('?entity=XX'))
    expect(invalid.status).toBe(422)
  })
})
