import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createAccount, Money } from '@cashdeck/domain'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { getContainer, resetContainer } from '@/server/container'
import { GET as safeToSpend } from '@/app/api/v1/home/personal/safe-to-spend/route'
import { GET as companySafeToSpend } from '@/app/api/v1/home/company/safe-to-spend/route'
import { GET as netWorth } from '@/app/api/v1/net-worth/route'

let session = ''
const TENANT = 'local'

function get(path: string, query = '') {
  return new Request(`http://localhost/api/v1/${path}${query}`, {
    headers: { authorization: `Bearer ${session}` },
  })
}

async function json(response: Response) {
  return { status: response.status, body: await response.json() }
}

beforeEach(async () => {
  vi.stubEnv('CASHDECK_API_TOKEN', STATIC_TOKEN)
  session = await signInTestDevice()
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

async function seeded() {
  const { deps } = getContainer()
  const personal = await deps.entities.findByKind(TENANT, 'PF')
  await deps.accounts.save(
    createAccount({
      id: 'chk',
      tenantId: TENANT,
      entityId: personal?.id ?? '',
      institutionId: 'bank',
      name: 'Checking',
      type: 'CHECKING',
      origin: 'MANUAL',
      balance: Money.of(310_000),
    }),
  )
}

describe('safe to spend route', () => {
  it('answers what is free to spend until the month ends', async () => {
    await seeded()
    const found = await json(
      await safeToSpend(get('home/personal/safe-to-spend')),
    )
    expect(found.status).toBe(200)
    expect(found.body.data).toMatchObject({
      cash: { cents: 310_000, currency: 'BRL' },
      total: { cents: 310_000 },
      income: null,
      lines: [],
    })
    expect(found.body.data.daily.cents).toBeGreaterThan(0)
  })

  it('answers for the company on its own path', async () => {
    await seeded()
    const found = await json(
      await companySafeToSpend(get('home/company/safe-to-spend')),
    )
    expect(found.status).toBe(200)
    expect(found.body.data).toMatchObject({
      entity: 'PJ',
      cash: { cents: 0 },
      lines: [],
    })
  })

  it('refuses a request without the token', async () => {
    const denied = await safeToSpend(
      new Request('http://localhost/api/v1/home/personal/safe-to-spend'),
    )
    expect(denied.status).toBe(401)
  })
})

describe('net worth route', () => {
  it('gives the current value and a month-end series', async () => {
    await seeded()
    const found = await json(await netWorth(get('net-worth', '?months=6')))
    expect(found.status).toBe(200)
    expect(found.body.data).toMatchObject({
      current: { cash: { cents: 310_000 }, total: { cents: 310_000 } },
      fromLastMonth: { amount: { cents: 0 }, percent: 0 },
    })
    expect(found.body.data.series).toHaveLength(7)
    const personal = await json(await netWorth(get('net-worth', '?entity=PF')))
    expect(personal.body.data.series).toHaveLength(13)
    expect(personal.body.data.entities).toEqual([
      expect.objectContaining({ kind: 'PF' }),
    ])
    const company = await json(await netWorth(get('net-worth', '?entity=PJ')))
    expect(company.body.data.entities).toEqual([
      expect.objectContaining({ kind: 'PJ' }),
    ])
    expect(company.body.data.current.cash.cents).toBe(0)
  })

  it('rejects a window out of range', async () => {
    const invalid = await json(await netWorth(get('net-worth', '?months=40')))
    expect(invalid.status).toBe(422)
  })
})
