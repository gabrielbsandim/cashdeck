import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@cashdeck/application'
import { FIPE_URL, FipeVehiclePrices } from '@/market/fipe-vehicle-prices'
import { ScriptedTransport } from '@/testing/scripted-transport'

const pickup = { type: 'CAR' as const, code: '005340-6', modelYear: 2020 }
const years = `${FIPE_URL}/cars/005340-6/years`

describe('FipeVehiclePrices', () => {
  it('reads the monthly prices of the model year and skips rows it cannot read', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${years}/2020-3/history`, {
        json: {
          model: ' Picape Exemplo 2.0 Diesel ',
          priceHistory: [
            { price: 'R$ 139.618,00', month: 'outubro de 2026' },
            { price: 'R$ 139.191,00', month: 'Setembro de 2026' },
            { price: 'R$ 1,00', month: 'brumário de 2026' },
            { price: '', month: 'agosto de 2026' },
            {},
          ],
        },
      })
      .on('GET', years, {
        json: [{ code: '2021-3' }, { code: '2020-3' }, {}],
      })

    const history = await new FipeVehiclePrices({
      transport: scripted.transport,
    }).history(pickup)

    expect(history).toEqual({
      model: 'Picape Exemplo 2.0 Diesel',
      prices: [
        { month: '2026-10', cents: 13961800 },
        { month: '2026-09', cents: 13919100 },
      ],
    })
  })

  it('falls back to the code for a model and to no prices', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${FIPE_URL}/motorcycles/811084-3/years/2019-1/history`, {
        json: {},
      })
      .on('GET', `${FIPE_URL}/motorcycles/811084-3/years`, {
        json: [{ code: '2019-1' }],
      })
    const prices = new FipeVehiclePrices({ transport: scripted.transport })
    expect(
      await prices.history({
        type: 'MOTORCYCLE',
        code: '811084-3',
        modelYear: 2019,
      }),
    ).toEqual({ model: '811084-3', prices: [] })
  })

  it('reads a missing code or year as not found and a failure as an error', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${FIPE_URL}/trucks/000000-0/years`, {
        status: 404,
        text: '{"error":"recurso não encontrado"}',
      })
      .on('GET', `${FIPE_URL}/cars/005340-6/years`, { json: [] })
      .on('GET', `${FIPE_URL}/cars/111111-1/years`, {
        status: 500,
        text: 'down',
      })
    const prices = new FipeVehiclePrices({ transport: scripted.transport })
    await expect(
      prices.history({ type: 'TRUCK', code: '000000-0', modelYear: 2010 }),
    ).rejects.toThrow(NotFoundError)
    await expect(prices.history(pickup)).rejects.toThrow(NotFoundError)
    await expect(
      prices.history({ ...pickup, code: '111111-1' }),
    ).rejects.toMatchObject({ status: 500 })
  })
})
