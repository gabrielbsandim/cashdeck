import { describe, expect, it } from 'vitest'
import { ValidationError } from '@cashdeck/domain'
import { createAssetSchema, updateAssetSchema } from '@/dtos/assets'
import { NotFoundError } from '@/errors/errors'
import { fullDeps } from '@/testing/deps.test-helpers'
import { FakeVehiclePrices } from '@/testing/investments'
import { importLoan } from '@/testing/loans.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { ASSETS_COLLECTION, makeAssets } from '@/use-cases/assets'
import { BILL_LINES_COLLECTION } from '@/use-cases/bill-lines'

const pickup = { type: 'CAR' as const, code: '005340-6', modelYear: 2020 }

const setup = () => {
  const vehiclePrices = new FakeVehiclePrices()
  vehiclePrices.histories.set(pickup.code, {
    model: 'Picape Exemplo 2.0 Diesel',
    prices: [
      { month: '2026-10', cents: 13961800 },
      { month: '2026-09', cents: 13919100 },
    ],
  })
  const deps = fullDeps({ vehiclePrices })
  return { deps, vehiclePrices, assets: makeAssets(deps) }
}

const home = {
  entity: 'PF' as const,
  kind: 'PROPERTY' as const,
  name: 'Apartamento',
  acquiredOn: '2026-08-10',
  value: 900000,
  loanId: null,
  rental: null,
}

describe('assets', () => {
  it('prices a vehicle from the FIPE table and names it after the model', async () => {
    const { assets } = setup()

    const view = await assets.create(TENANT, {
      entity: 'PF',
      kind: 'VEHICLE',
      acquiredOn: '2022-03-01',
      fipe: pickup,
      loanId: null,
      rental: null,
    })

    expect(view).toMatchObject({
      kind: 'VEHICLE',
      name: 'Picape Exemplo 2.0 Diesel',
      value: { cents: 13961800 },
      valuedOn: '2026-10-01',
      change: { amount: { cents: 42700 }, percent: 0.3 },
      fipe: pickup,
      loan: null,
      equity: { cents: 13961800 },
    })
  })

  it('takes a value by hand over the table and lists by kind with totals', async () => {
    const { deps, assets } = setup()
    const loanId = await importLoan(deps)
    await assets.create(TENANT, {
      entity: 'PF',
      kind: 'VEHICLE',
      name: 'Picape',
      acquiredOn: '2022-03-01',
      value: 13000000,
      fipe: pickup,
      loanId: null,
      rental: null,
    })
    await assets.create(TENANT, { ...home, loanId })

    const list = await assets.list(TENANT)

    expect(list.items.map(item => [item.name, item.value.cents])).toEqual([
      ['Apartamento', 900000],
      ['Picape', 13000000],
    ])
    expect(list.items[0]?.loan).toEqual({
      id: loanId,
      name: 'Bradesco 1234567',
      balance: { cents: 200000, currency: 'BRL' },
    })
    expect(list).toMatchObject({
      value: { cents: 13900000 },
      loanDebt: { cents: 200000 },
      equity: { cents: 13700000 },
    })
  })

  it('revalues, renames, links, marks sold and removes an asset', async () => {
    const { deps, assets } = setup()
    const loanId = await importLoan(deps)
    const { id } = await assets.create(TENANT, home)

    const revalued = await assets.update(TENANT, id, {
      name: 'Apartamento alugado',
      value: 950000,
      valuedOn: '2026-09-01',
      loanId,
    })
    expect(revalued).toMatchObject({
      name: 'Apartamento alugado',
      value: { cents: 900000 },
      change: { amount: { cents: -50000 } },
      loan: { id: loanId },
      equity: { cents: 700000 },
    })

    const today = await assets.update(TENANT, id, { value: 1000000 })
    expect(today.value.cents).toBe(1000000)
    expect(today.loan?.id).toBe(loanId)

    const sold = await assets.update(TENANT, id, {
      loanId: null,
      soldOn: '2026-10-01',
    })
    expect(sold).toMatchObject({
      soldOn: '2026-10-01',
      value: { cents: 0 },
      loan: null,
      name: 'Apartamento alugado',
    })

    expect(await assets.remove(TENANT, id)).toEqual({ id })
    await expect(assets.remove(TENANT, id)).rejects.toThrow(NotFoundError)
  })

  it('charges the tenant the rent and the gas of the latest building bill', async () => {
    const { deps, assets } = setup()
    const loanId = await importLoan(deps)
    const bill = (id: string, payee: string, dueDate: string, gas: number) =>
      deps.documents.put(TENANT, BILL_LINES_COLLECTION, id, {
        billId: id,
        payee,
        dueDate,
        total: 46104 + gas,
        lines: [
          { description: 'Taxas de condomínio', cents: 46104 },
          { description: 'Consumo de gás', cents: gas },
        ],
        attachmentId: `${id}-pdf`,
      })
    await bill('b-sep', 'CONDOMÍNIO JARDIM AZUL', '2026-09-10', 15597)
    await bill('b-oct', 'CONDOMÍNIO JARDIM AZUL', '2026-10-10', 13665)
    await bill('b-other', 'Residencial Jardim Verde', '2026-11-10', 9000)
    const rental = {
      rent: 160000,
      passThrough: ['gas'],
      billFrom: 'Jardim Azul',
    }

    const rented = await assets.create(TENANT, { ...home, loanId, rental })

    expect(rented.rental).toEqual({
      rent: { cents: 160000, currency: 'BRL' },
      passThrough: ['gas'],
      billFrom: 'Jardim Azul',
      charge: {
        billId: 'b-oct',
        dueDate: '2026-10-10',
        billTotal: { cents: 59769, currency: 'BRL' },
        passedOn: [
          {
            description: 'Consumo de gás',
            amount: { cents: 13665, currency: 'BRL' },
          },
        ],
        total: { cents: 173665, currency: 'BRL' },
        ownerCost: { cents: 46104, currency: 'BRL' },
        attachmentId: 'b-oct-pdf',
        installment: { cents: 108500, currency: 'BRL' },
        result: { cents: 5396, currency: 'BRL' },
      },
    })

    const unlinked = await assets.update(TENANT, rented.id, { loanId: null })
    expect(unlinked.rental?.charge).toMatchObject({
      installment: null,
      result: { cents: 113896 },
    })
    const elsewhere = await assets.update(TENANT, rented.id, {
      rental: { ...rental, billFrom: 'Vila Nova' },
    })
    expect(elsewhere.rental?.charge).toBeNull()
    const kept = await assets.update(TENANT, rented.id, { name: 'Apto 2' })
    expect(kept.rental?.billFrom).toBe('Vila Nova')
    const ended = await assets.update(TENANT, rented.id, { rental: null })
    expect(ended.rental).toBeNull()
  })

  it('reads a good stored before renting out was tracked as not rented', async () => {
    const { deps, assets } = setup()
    const { id } = await assets.create(TENANT, home)
    const stored = await deps.documents.get<Record<string, unknown>>(
      TENANT,
      ASSETS_COLLECTION,
      id,
    )
    const { rental: _rental, ...older } = stored ?? {}
    await deps.documents.put(TENANT, ASSETS_COLLECTION, id, older)

    expect((await assets.list(TENANT)).items[0]?.rental).toBeNull()
    expect(
      (await assets.update(TENANT, id, { name: 'Casa' })).rental,
    ).toBeNull()
  })

  it('refuses a model year with no price and a value from a future day', async () => {
    const { assets, vehiclePrices } = setup()
    vehiclePrices.histories.set('009999-9', { model: 'Novo', prices: [] })
    await expect(
      assets.create(TENANT, {
        entity: 'PF',
        kind: 'VEHICLE',
        acquiredOn: '2026-10-01',
        fipe: { ...pickup, code: '009999-9' },
        loanId: null,
        rental: null,
      }),
    ).rejects.toThrow(ValidationError)
    const { id } = await assets.create(TENANT, home)
    await expect(
      assets.update(TENANT, id, { value: 1, valuedOn: '2026-10-09' }),
    ).rejects.toThrow(ValidationError)
  })

  it('moves a vehicle to another model, then to a value by hand', async () => {
    const { assets, vehiclePrices } = setup()
    const sedan = { ...pickup, code: '007777-7' }
    vehiclePrices.histories.set(sedan.code, {
      model: 'Sedan Exemplo 1.6 Flex',
      prices: [{ month: '2026-10', cents: 5_000_000 }],
    })
    const { id } = await assets.create(TENANT, {
      entity: 'PF',
      kind: 'VEHICLE',
      acquiredOn: '2022-03-01',
      fipe: pickup,
      loanId: null,
      rental: null,
    })

    const moved = await assets.update(TENANT, id, {
      fipe: sedan,
      acquiredOn: '2021-01-10',
    })
    expect(moved).toMatchObject({
      name: 'Sedan Exemplo 1.6 Flex',
      acquiredOn: '2021-01-10',
      value: { cents: 5_000_000 },
      change: { percent: 0 },
      fipe: sedan,
    })

    const byHand = await assets.update(TENANT, id, {
      fipe: null,
      name: 'Carro da casa',
      value: 4_800_000,
    })
    expect(byHand).toMatchObject({
      name: 'Carro da casa',
      acquiredOn: '2021-01-10',
      value: { cents: 4_800_000 },
      fipe: null,
    })
  })

  it('refuses a FIPE model on a property or without prices', async () => {
    const { assets, vehiclePrices } = setup()
    vehiclePrices.histories.set('009999-9', { model: 'Novo', prices: [] })
    const { id } = await assets.create(TENANT, home)
    await expect(assets.update(TENANT, id, { fipe: pickup })).rejects.toThrow(
      ValidationError,
    )
    const car = await assets.create(TENANT, {
      entity: 'PF',
      kind: 'VEHICLE',
      acquiredOn: '2022-03-01',
      fipe: pickup,
      loanId: null,
      rental: null,
    })
    await expect(
      assets.update(TENANT, car.id, { fipe: { ...pickup, code: '009999-9' } }),
    ).rejects.toThrow(ValidationError)
  })

  it('refuses a loan that does not exist', async () => {
    const { assets } = setup()
    await expect(
      assets.create(TENANT, { ...home, loanId: 'nowhere' }),
    ).rejects.toThrow(NotFoundError)
    const { id } = await assets.create(TENANT, home)
    await expect(
      assets.update(TENANT, id, { loanId: 'nowhere' }),
    ).rejects.toThrow(NotFoundError)
  })

  it('refreshes the vehicles still owned and keeps the last price of one the table lost', async () => {
    const { assets, vehiclePrices } = setup()
    const retired = { ...pickup, code: '001001-1' }
    vehiclePrices.histories.set(retired.code, {
      model: 'Sedan Exemplo',
      prices: [{ month: '2026-10', cents: 5000000 }],
    })
    const vehicle = (fipe: typeof pickup) =>
      assets.create(TENANT, {
        entity: 'PF',
        kind: 'VEHICLE',
        acquiredOn: '2022-03-01',
        fipe,
        loanId: null,
        rental: null,
      })
    const tracked = await vehicle(pickup)
    const lost = await vehicle(retired)
    const sold = await vehicle(pickup)
    await assets.update(TENANT, sold.id, { soldOn: '2026-10-02' })
    await assets.create(TENANT, home)
    vehiclePrices.histories.set(pickup.code, {
      model: 'Picape Exemplo 2.0 Diesel',
      prices: [{ month: '2026-10', cents: 13800000 }],
    })
    vehiclePrices.histories.delete(retired.code)

    expect(await assets.refreshPrices(TENANT)).toEqual({
      refreshed: 1,
      failed: 1,
    })

    const { items } = await assets.list(TENANT)
    const valueOf = (id: string) =>
      items.find(item => item.id === id)?.value.cents
    expect(valueOf(tracked.id)).toBe(13800000)
    expect(valueOf(lost.id)).toBe(5000000)
    expect(valueOf(sold.id)).toBe(0)
  })
})

describe('asset input', () => {
  it('asks for a value or a FIPE code, a FIPE code only on a vehicle, and a name', () => {
    const base = { kind: 'OTHER', name: 'Relógio', acquiredOn: '2026-01-01' }
    expect(createAssetSchema.safeParse(base).error?.issues[0]?.path).toEqual([
      'value',
    ])
    expect(
      createAssetSchema.safeParse({ ...base, fipe: pickup }).error?.issues[0]
        ?.path,
    ).toEqual(['fipe'])
    expect(
      createAssetSchema.safeParse({ ...base, name: undefined, value: 100 })
        .error?.issues[0]?.path,
    ).toEqual(['name'])
    expect(createAssetSchema.parse({ ...base, value: 100 })).toMatchObject({
      entity: 'PF',
      loanId: null,
    })
    expect(updateAssetSchema.parse({ soldOn: null })).toEqual({ soldOn: null })
  })
})
