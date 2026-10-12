import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createTransaction, Money, toLocalDate } from '@cashdeck/domain'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { getContainer, resetContainer } from '@/server/container'
import { POST as createAccount } from '@/app/api/v1/accounts/route'
import { GET as latestRecap } from '@/app/api/v1/recaps/latest/route'
import { GET as monthlyRecap } from '@/app/api/v1/recaps/[month]/route'
import { GET as recapCron } from '@/app/api/cron/monthly-recap/route'

let session = ''

type Handler = (request: Request, context: never) => Promise<Response>

async function call(
  handler: unknown,
  options: { params?: Record<string, string>; query?: string } = {},
) {
  const request = new Request(
    `http://localhost/api/v1/test${options.query ?? ''}`,
    { headers: { authorization: `Bearer ${session}` } },
  )
  const context = { params: Promise.resolve(options.params ?? {}) }
  const response = await (handler as Handler)(request, context as never)
  return { status: response.status, body: await response.json() }
}

function shiftMonth(month: string, by: number): string {
  const [year, number] = month.split('-').map(Number) as [number, number]
  const index = year * 12 + number - 1 + by
  return `${Math.floor(index / 12)}-${String((index % 12) + 1).padStart(2, '0')}`
}

const thisMonth = () => toLocalDate(new Date()).slice(0, 7)
const closedMonth = () => shiftMonth(thisMonth(), -1)

async function seedClosedMonth() {
  const created = await createAccount(
    new Request('http://localhost/api/v1/accounts', {
      method: 'POST',
      headers: { authorization: `Bearer ${session}` },
      body: JSON.stringify({
        entity: 'PF',
        institution: 'Bank',
        name: 'Checking',
        type: 'CHECKING',
      }),
    }),
  )
  const accountId = (await created.json()).data.id as string
  const month = closedMonth()
  for (const [id, cents, day] of [
    ['salary', 500_000, '05'],
    ['market', -120_000, '10'],
  ] as const) {
    await getContainer().deps.transactions.save(
      createTransaction({
        id,
        tenantId: 'local',
        accountId,
        amount: Money.of(cents),
        bookedOn: `${month}-${day}`,
        description: id,
      }),
    )
  }
  return month
}

beforeEach(async () => {
  vi.stubEnv('CASHDECK_API_TOKEN', STATIC_TOKEN)
  session = await signInTestDevice()
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

describe('monthly recaps', () => {
  it('tells the last closed month and any closed month asked by name', async () => {
    const month = await seedClosedMonth()
    const latest = await call(latestRecap, { query: '?entity=PF&locale=en' })
    expect(latest.status).toBe(200)
    expect(latest.body.data).toMatchObject({
      month,
      entity: 'PF',
      flow: {
        income: { cents: 500_000 },
        expenses: { cents: 120_000 },
        net: { cents: 380_000 },
      },
      savings: { percent: 76 },
      story: { locale: 'en', source: 'AI' },
    })
    const named = await call(monthlyRecap, {
      params: { month },
      query: '?entity=PF&locale=en',
    })
    expect(named.body.data).toEqual(latest.body.data)
  })

  it('refuses a month that has not closed or is malformed', async () => {
    const open = await call(monthlyRecap, { params: { month: thisMonth() } })
    expect(open.status).toBe(422)
    const malformed = await call(monthlyRecap, { params: { month: '2026' } })
    expect(malformed.status).toBe(422)
    const locale = await call(latestRecap, { query: '?locale=fr' })
    expect(locale.status).toBe(422)
  })

  it('pushes the recap once from the cron route', async () => {
    vi.stubEnv('CRON_SECRET', 'secret')
    const month = await seedClosedMonth()
    const cron = async () => {
      const response = await recapCron(
        new Request('http://localhost/api/cron/monthly-recap', {
          headers: { authorization: 'Bearer secret' },
        }),
      )
      return (await response.json()).data
    }
    expect(await cron()).toMatchObject({
      source: 'monthly-recap',
      month,
      sent: true,
    })
    expect(await cron()).toMatchObject({ month, sent: false })
    const inbox = await getContainer().deps.alertStore.list(
      'local',
      {},
      { limit: 10, cursor: null },
    )
    expect(inbox.items.map(alert => alert.type)).toContain('MONTHLY_RECAP')
  })
})
