import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { resetContainer } from '@/server/container'
import { GET as viewPlan } from '@/app/api/v1/plan/route'
import { PUT as saveSettings } from '@/app/api/v1/plan/settings/route'
import { PUT as reorder } from '@/app/api/v1/plan/order/route'
import { POST as createGoal } from '@/app/api/v1/plan/goals/route'
import {
  DELETE as removeGoal,
  PUT as updateGoal,
} from '@/app/api/v1/plan/goals/[id]/route'

let session = ''

type Handler = (request: Request, context: never) => Promise<Response>

async function call(
  handler: unknown,
  method: string,
  options: { body?: unknown; params?: Record<string, string> } = {},
) {
  const request = new Request('http://localhost/api/v1/plan', {
    method,
    headers: { authorization: `Bearer ${session}` },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  })
  const context = { params: Promise.resolve(options.params ?? {}) }
  const response = await (handler as Handler)(request, context as never)
  const json = await response.json()
  return { status: response.status, body: json.data ?? json }
}

beforeEach(async () => {
  vi.stubEnv('CASHDECK_API_TOKEN', STATIC_TOKEN)
  session = await signInTestDevice()
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

const names = (body: { goals: { name: string }[] }) =>
  body.goals.map(goal => goal.name)

describe('life plan routes', () => {
  it('builds a plan, reorders it and edits its goals', async () => {
    const empty = await call(viewPlan, 'GET')
    expect(empty.status).toBe(200)
    expect(empty.body).toMatchObject({ goals: [], reserveMonths: 6 })

    const trips = await call(createGoal, 'POST', {
      body: { kind: 'YEARLY', name: 'Trips', yearly: 1_700_000 },
    })
    expect(trips.status).toBe(201)
    const tripId = trips.body.goals[0].id as string
    const phone = await call(createGoal, 'POST', {
      body: { kind: 'PURCHASE', name: 'Phone', price: 600_000 },
    })
    const phoneId = phone.body.goals[1].id as string

    const ordered = await call(reorder, 'PUT', { body: { ids: [phoneId] } })
    expect(names(ordered.body)).toEqual(['Phone', 'Trips'])

    const edited = await call(updateGoal, 'PUT', {
      params: { id: tripId },
      body: { kind: 'YEARLY', name: 'Holidays', yearly: 1_200_000 },
    })
    expect(edited.body.yearlyProvision.cents).toBe(100_000)

    const settings = await call(saveSettings, 'PUT', {
      body: { reserveMonths: 3, yearlyYield: 5, monthlySavings: 400_000 },
    })
    expect(settings.body).toMatchObject({
      reserveMonths: 3,
      monthlySavings: { cents: 400_000 },
      free: { cents: 300_000 },
    })

    const left = await call(removeGoal, 'DELETE', { params: { id: phoneId } })
    expect(names(left.body)).toEqual(['Holidays'])
  })

  it('rejects a bad goal', async () => {
    const response = await call(createGoal, 'POST', {
      body: { kind: 'MILESTONE', name: 'Million', metric: 'GOLD', target: 1 },
    })
    expect(response.status).toBe(422)
  })
})
