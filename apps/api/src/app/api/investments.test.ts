import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { addDays, Money, toLocalDate } from '@cashdeck/domain'
import { getContainer, resetContainer } from '@/server/container'
import { GET as listInvestments } from '@/app/api/v1/investments/route'
import { GET as getInvestment } from '@/app/api/v1/investments/[id]/route'
import { GET as investmentPerformance } from '@/app/api/v1/investments/performance/route'

const TOKEN = 'test-token-0123456789'
const TENANT = 'local'

function get(query = '') {
  return new Request(`http://localhost/api/v1/investments${query}`, {
    headers: { authorization: `Bearer ${TOKEN}` },
  })
}

const params = (id: string) => ({ params: Promise.resolve({ id }) })

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

async function seeded() {
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
  return deps
}

describe('investments route', () => {
  it('sums the positions held and filters by entity', async () => {
    await seeded()
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

  it('reports the yield of a period against the CDI', async () => {
    const deps = await seeded()
    const today = toLocalDate(new Date())
    await deps.investments.saveSnapshots([
      {
        tenantId: TENANT,
        investmentId: 'inv1',
        day: addDays(today, -40),
        balanceCents: 100_000,
        estimated: true,
      },
    ])
    await deps.investments.saveMovements([
      {
        id: 'm1',
        tenantId: TENANT,
        investmentId: 'inv1',
        externalId: 'tx1',
        kind: 'BUY',
        occurredOn: addDays(today, -10),
        amountCents: 3_000,
        quantity: null,
        unitPrice: null,
      },
    ])
    await deps.indexRates.save('CDI', [
      { day: addDays(today, -1), value: 0.05 },
    ])

    const month = await json(await investmentPerformance(get('/performance')))
    expect(month.status).toBe(200)
    expect(month.body.data).toMatchObject({
      period: 'MONTH',
      from: addDays(today, -30),
      to: today,
      start: { cents: 100_000, currency: 'BRL' },
      end: { cents: 105_000 },
      contributions: { cents: 3_000 },
      yield: { cents: 2_000 },
      cdiPercent: 0.05,
      estimated: true,
      positions: [{ id: 'inv1', yield: { cents: 2_000 } }],
    })
    expect(month.body.data.series).toHaveLength(31)

    const year = await json(
      await investmentPerformance(get('/performance?period=YEAR&entity=PJ')),
    )
    expect(year.body.data).toMatchObject({ period: 'YEAR', positions: [] })

    const invalid = await investmentPerformance(get('/performance?period=DAY'))
    expect(invalid.status).toBe(422)
  })

  it('details a position with its movements and 404s an unknown one', async () => {
    await seeded()
    const detail = await json(
      await getInvestment(get('/inv1?period=WEEK'), params('inv1')),
    )
    expect(detail.status).toBe(200)
    expect(detail.body.data).toMatchObject({
      position: { id: 'inv1', invested: { cents: 100_000 } },
      performance: { period: 'WEEK', end: { cents: 105_000 } },
      movements: [],
    })

    const missing = await getInvestment(get('/nope'), params('nope'))
    expect(missing.status).toBe(404)
  })
})
