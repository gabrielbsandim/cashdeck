import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { signInTestDevice, STATIC_TOKEN } from '@/app/api/sign-in.test-helpers'
import { resetContainer } from '@/server/container'
import {
  GET as listAssets,
  POST as createAsset,
} from '@/app/api/v1/assets/route'
import {
  DELETE as removeAsset,
  PATCH as updateAsset,
} from '@/app/api/v1/assets/[id]/route'
import { GET as pricesCron } from '@/app/api/cron/vehicle-prices/route'

let session = ''

function request(path: string, method = 'GET', body?: unknown) {
  return new Request(`http://localhost/api/v1/${path}`, {
    method,
    headers: {
      authorization: `Bearer ${session}`,
      'content-type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
}

const withId = (id: string) => ({ params: Promise.resolve({ id }) })

async function json(response: Response) {
  return { status: response.status, body: await response.json() }
}

const home = {
  kind: 'PROPERTY',
  name: 'Apartamento',
  acquiredOn: '2025-06-10',
  value: 50_000_000,
}

beforeEach(async () => {
  vi.stubEnv('CASHDECK_API_TOKEN', STATIC_TOKEN)
  session = await signInTestDevice()
})

afterEach(() => {
  resetContainer()
  vi.unstubAllEnvs()
})

describe('asset routes', () => {
  it('adds, lists, revalues and removes a good', async () => {
    const created = await json(
      await createAsset(request('assets', 'POST', home)),
    )
    expect(created.status).toBe(201)
    expect(created.body.data).toMatchObject({
      entity: 'PF',
      name: 'Apartamento',
      value: { cents: 50_000_000 },
      equity: { cents: 50_000_000 },
    })
    const { id } = created.body.data

    const updated = await json(
      await updateAsset(
        request(`assets/${id}`, 'PATCH', { value: 52_000_000 }),
        withId(id),
      ),
    )
    expect(updated.body.data.value.cents).toBe(52_000_000)

    const listed = await json(await listAssets(request('assets')))
    expect(listed.body.data).toMatchObject({
      items: [{ id }],
      value: { cents: 52_000_000 },
    })

    const removed = await json(
      await removeAsset(request(`assets/${id}`, 'DELETE'), withId(id)),
    )
    expect(removed).toMatchObject({ status: 200, body: { data: { id } } })
  })

  it('rejects a good without a value, an unknown loan and an unknown good', async () => {
    const valueless = await createAsset(
      request('assets', 'POST', { ...home, value: undefined }),
    )
    expect(valueless.status).toBe(422)
    const unlinked = await createAsset(
      request('assets', 'POST', { ...home, loanId: 'none' }),
    )
    expect(unlinked.status).toBe(404)
    const unknown = await updateAsset(
      request('assets/none', 'PATCH', { value: 1 }),
      withId('none'),
    )
    expect(unknown.status).toBe(404)
  })

  it('refreshes vehicle prices from the cron route', async () => {
    vi.stubEnv('CRON_SECRET', 'secret')
    const response = await pricesCron(
      new Request('http://localhost/api/cron/vehicle-prices', {
        headers: { authorization: 'Bearer secret' },
      }),
    )
    expect((await response.json()).data).toMatchObject({
      refreshed: 0,
      failed: 0,
    })
  })
})
