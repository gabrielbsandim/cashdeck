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
import { GET as vehicleBrands } from '@/app/api/v1/vehicles/brands/route'
import { GET as vehicleYears } from '@/app/api/v1/vehicles/years/route'
import { GET as vehicleModels } from '@/app/api/v1/vehicles/models/route'
import { GET as vehiclePrice } from '@/app/api/v1/vehicles/price/route'

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
  vi.unstubAllGlobals()
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

  it('walks the FIPE table from brand to a priced model', async () => {
    const table: Record<string, unknown> = {
      '/cars/brands': [{ code: '1', name: 'Alfa Exemplo' }],
      '/cars/brands/1/years': [{ code: '2020-5', name: '2020 Flex' }],
      '/cars/brands/1/years/2020-5/models': [
        { code: '10', name: 'Hatch Exemplo 1.0 Flex' },
      ],
      '/cars/brands/1/models/10/years/2020-5': {
        codeFipe: '001234-5',
        modelYear: 2020,
        model: 'Hatch Exemplo 1.0 Flex',
        price: 'R$ 58.900,00',
      },
    }
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) =>
        Response.json(table[new URL(String(url)).pathname.slice(7)]),
      ),
    )
    // The container binds fetch when built.
    resetContainer()
    session = await signInTestDevice()

    const brands = await json(
      await vehicleBrands(request('vehicles/brands?type=CAR')),
    )
    expect(brands.body.data.items).toEqual([
      { code: '1', name: 'Alfa Exemplo' },
    ])
    const years = await json(
      await vehicleYears(request('vehicles/years?type=CAR&brand=1')),
    )
    expect(years.body.data.items).toEqual([{ code: '2020', name: '2020' }])
    const models = await json(
      await vehicleModels(
        request('vehicles/models?type=CAR&brand=1&modelYear=2020'),
      ),
    )
    expect(models.body.data.items).toEqual([
      { code: '10', name: 'Hatch Exemplo 1.0 Flex', year: '2020-5' },
    ])
    const price = await json(
      await vehiclePrice(
        request('vehicles/price?type=CAR&brand=1&year=2020-5&model=10'),
      ),
    )
    expect(price.body.data).toMatchObject({
      fipe: { type: 'CAR', code: '001234-5', modelYear: 2020 },
      price: { cents: 5_890_000 },
    })
    const invalid = await vehicleModels(
      request('vehicles/models?type=BOAT&brand=1&modelYear=2020'),
    )
    expect(invalid.status).toBe(422)
  })
})
