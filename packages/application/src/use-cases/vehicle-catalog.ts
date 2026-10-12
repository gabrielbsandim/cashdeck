import { Money } from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type VehicleBrandsQuery,
  type VehicleModelsQuery,
  type VehicleModelsView,
  type VehicleOptionsView,
  type VehiclePriceQuery,
  type VehiclePriceView,
  type VehicleYearsQuery,
} from '@/dtos/vehicles'
import { type VehicleOption } from '@/ports/investments'
import { type Deps } from '@/use-cases/deps'
import { today } from '@/use-cases/shared'

type CatalogDeps = Pick<Deps, 'vehiclePrices' | 'clock'>

const byName = (a: VehicleOption, b: VehicleOption) =>
  a.name.localeCompare(b.name, 'pt-BR')

// "2020-5" is model year 2020 on flex fuel.
const modelYearOf = (year: string) => Number(year.split('-')[0])

// Walks the FIPE table brand, model year, model, so a vehicle is found
// without knowing its code.
export function makeVehicleCatalog(deps: CatalogDeps) {
  // The table lists a brand-new model as year 32000; a model year runs one
  // ahead of the calendar.
  const yearsOf = async ({ type, brand }: VehicleYearsQuery) => {
    const latest = Number(today(deps.clock.now()).slice(0, 4)) + 1
    const years = await deps.vehiclePrices.years(type, brand)
    return years
      .map(year => year.code)
      .filter(code => {
        const modelYear = modelYearOf(code)
        return modelYear >= 1950 && modelYear <= latest
      })
  }

  return {
    async brands({ type }: VehicleBrandsQuery): Promise<VehicleOptionsView> {
      const brands = await deps.vehiclePrices.brands(type)
      return { items: [...brands].sort(byName) }
    },

    // One entry a model year, whatever the fuels.
    async years(query: VehicleYearsQuery): Promise<VehicleOptionsView> {
      const years = new Set((await yearsOf(query)).map(modelYearOf))
      return {
        items: [...years]
          .sort((a, b) => b - a)
          .map(year => ({ code: String(year), name: String(year) })),
      }
    },

    async models(query: VehicleModelsQuery): Promise<VehicleModelsView> {
      const years = (await yearsOf(query)).filter(
        year => modelYearOf(year) === query.modelYear,
      )
      const models = await Promise.all(
        years.map(async year =>
          (await deps.vehiclePrices.models(query.type, query.brand, year)).map(
            model => ({ ...model, year }),
          ),
        ),
      )
      return { items: models.flat().sort(byName) }
    },

    async price(query: VehiclePriceQuery): Promise<VehiclePriceView> {
      const vehicle = await deps.vehiclePrices.vehicle(
        query.type,
        query.brand,
        query.year,
        query.model,
      )
      return {
        fipe: {
          type: query.type,
          code: vehicle.code,
          modelYear: vehicle.modelYear,
        },
        model: vehicle.model,
        price: money(Money.of(vehicle.cents)),
      }
    },
  }
}

export type VehicleCatalog = ReturnType<typeof makeVehicleCatalog>
