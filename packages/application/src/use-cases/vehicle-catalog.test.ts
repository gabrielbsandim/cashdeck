import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import { fullDeps } from '@/testing/deps.test-helpers'
import { FakeVehiclePrices } from '@/testing/investments'
import { makeVehicleCatalog } from '@/use-cases/vehicle-catalog'

const setup = () => {
  const vehiclePrices = new FakeVehiclePrices()
  vehiclePrices.catalog.set('CAR', [
    { code: '2', name: 'Zeta Motors' },
    { code: '1', name: 'Alfa Exemplo' },
  ])
  vehiclePrices.catalog.set('CAR/1', [
    { code: '32000-5', name: '32000 Flex' },
    { code: '2028-5', name: '2028 Flex' },
    { code: '2027-5', name: '2027 Flex' },
    { code: '2020-1', name: '2020 Gasolina' },
    { code: '2020-5', name: '2020 Flex' },
    { code: '1949-1', name: '1949 Gasolina' },
  ])
  vehiclePrices.catalog.set('CAR/1/2020-1', [
    { code: '30', name: 'Sedan Exemplo 2.0 Turbo' },
  ])
  vehiclePrices.catalog.set('CAR/1/2020-5', [
    { code: '10', name: 'Hatch Exemplo 1.0 Flex' },
  ])
  vehiclePrices.vehicles.set('CAR/1/2020-5/10', {
    code: '001234-5',
    modelYear: 2020,
    model: 'Hatch Exemplo 1.0 Flex',
    cents: 5_890_000,
  })
  const catalog = makeVehicleCatalog(fullDeps({ vehiclePrices }))
  return { catalog, vehiclePrices }
}

describe('vehicle catalog', () => {
  it('lists the brands by name', async () => {
    const { catalog } = setup()
    expect(await catalog.brands({ type: 'CAR' })).toEqual({
      items: [
        { code: '1', name: 'Alfa Exemplo' },
        { code: '2', name: 'Zeta Motors' },
      ],
    })
  })

  it('lists one entry a model year, up to next year and none brand new', async () => {
    const { catalog } = setup()
    expect(await catalog.years({ type: 'CAR', brand: '1' })).toEqual({
      items: [
        { code: '2027', name: '2027' },
        { code: '2020', name: '2020' },
      ],
    })
  })

  it('joins the models of every fuel in a model year', async () => {
    const { catalog } = setup()
    expect(
      await catalog.models({ type: 'CAR', brand: '1', modelYear: 2020 }),
    ).toEqual({
      items: [
        { code: '10', name: 'Hatch Exemplo 1.0 Flex', year: '2020-5' },
        { code: '30', name: 'Sedan Exemplo 2.0 Turbo', year: '2020-1' },
      ],
    })
  })

  it('prices a model with its FIPE code', async () => {
    const { catalog } = setup()
    expect(
      await catalog.price({
        type: 'CAR',
        brand: '1',
        year: '2020-5',
        model: '10',
      }),
    ).toEqual({
      fipe: { type: 'CAR', code: '001234-5', modelYear: 2020 },
      model: 'Hatch Exemplo 1.0 Flex',
      price: { cents: 5_890_000, currency: 'BRL' },
    })
    await expect(
      catalog.price({ type: 'CAR', brand: '1', year: '2020-1', model: '10' }),
    ).rejects.toThrow(NotFoundError)
    await expect(catalog.brands({ type: 'TRUCK' })).rejects.toThrow(
      NotFoundError,
    )
  })
})
