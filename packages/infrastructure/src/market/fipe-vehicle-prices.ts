import {
  type CatalogVehicle,
  type FipeVehicle,
  NotFoundError,
  type VehicleOption,
  type VehiclePriceHistory,
  type VehiclePrices,
  type VehicleType,
} from '@cashdeck/application'
import {
  bodySummary,
  type HttpResponse,
  isSuccess,
  ProviderHttpError,
  readJson,
  send,
  type Transport,
} from '@/http/transport'

export const FIPE_URL = 'https://fipe.parallelum.com.br/api/v2'

const PATHS: Record<VehicleType, string> = {
  CAR: 'cars',
  MOTORCYCLE: 'motorcycles',
  TRUCK: 'trucks',
}

const MONTHS = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
]

type YearRow = { code?: string }

type OptionRow = { code?: string | number; name?: string }

type VehicleBody = {
  codeFipe?: string
  modelYear?: number
  model?: string
  price?: string
}

type HistoryBody = {
  model?: string
  priceHistory?: Array<{ price?: string; month?: string }>
}

// "outubro de 2026" to 2026-10.
function monthOf(label: string | undefined): string | null {
  const match = /^(\S+) de (\d{4})$/.exec(label?.trim().toLowerCase() ?? '')
  const index = MONTHS.indexOf(match?.[1] ?? '')
  return match && index >= 0
    ? `${match[2]}-${String(index + 1).padStart(2, '0')}`
    : null
}

// "R$ 139.618,00" to cents.
function centsOf(price: string | undefined): number | null {
  const digits = (price ?? '').replace(/\D/g, '')
  return digits ? Number(digits) : null
}

export type FipeVehiclePricesDeps = { transport: Transport }

// The FIPE table through Parallelum's public mirror: keyless, a few hundred
// requests a day, and the last few months of a model year.
export class FipeVehiclePrices implements VehiclePrices {
  constructor(private readonly deps: FipeVehiclePricesDeps) {}

  async history(vehicle: FipeVehicle): Promise<VehiclePriceHistory> {
    const base = `${FIPE_URL}/${PATHS[vehicle.type]}/${encodeURIComponent(vehicle.code)}/years`
    const years = parse<YearRow[]>(await this.get(base))
    const year = years.find(row =>
      row.code?.startsWith(`${vehicle.modelYear}-`),
    )?.code
    if (!year) {
      throw new NotFoundError('FIPE model year')
    }
    const body = parse<HistoryBody>(
      await this.get(`${base}/${encodeURIComponent(year)}/history`),
    )
    return {
      model: body.model?.trim() || vehicle.code,
      prices: (body.priceHistory ?? []).flatMap(row => {
        const month = monthOf(row.month)
        const cents = centsOf(row.price)
        return month && cents ? [{ month, cents }] : []
      }),
    }
  }

  brands(type: VehicleType): Promise<VehicleOption[]> {
    return this.options(`${FIPE_URL}/${PATHS[type]}/brands`)
  }

  years(type: VehicleType, brand: string): Promise<VehicleOption[]> {
    return this.options(`${this.brand(type, brand)}/years`)
  }

  models(
    type: VehicleType,
    brand: string,
    year: string,
  ): Promise<VehicleOption[]> {
    return this.options(
      `${this.brand(type, brand)}/years/${encodeURIComponent(year)}/models`,
    )
  }

  async vehicle(
    type: VehicleType,
    brand: string,
    year: string,
    model: string,
  ): Promise<CatalogVehicle> {
    const body = parse<VehicleBody>(
      await this.get(
        `${this.brand(type, brand)}/models/${encodeURIComponent(model)}/years/${encodeURIComponent(year)}`,
      ),
    )
    const cents = centsOf(body.price)
    if (!body.codeFipe || !body.modelYear || !cents) {
      throw new NotFoundError('FIPE vehicle')
    }
    return {
      code: body.codeFipe,
      modelYear: body.modelYear,
      model: body.model?.trim() || body.codeFipe,
      cents,
    }
  }

  private brand(type: VehicleType, brand: string) {
    return `${FIPE_URL}/${PATHS[type]}/brands/${encodeURIComponent(brand)}`
  }

  private async options(url: string): Promise<VehicleOption[]> {
    return parse<OptionRow[]>(await this.get(url)).flatMap(row =>
      row.code !== undefined && row.name?.trim()
        ? [{ code: String(row.code), name: row.name.trim() }]
        : [],
    )
  }

  private get(url: string) {
    return send(this.deps.transport, { method: 'GET', url })
  }
}

function parse<T>(response: HttpResponse): T {
  if (response.status === 404) {
    throw new NotFoundError('FIPE vehicle')
  }
  if (!isSuccess(response)) {
    throw new ProviderHttpError(
      'FIPE',
      response.status,
      bodySummary(response.text),
    )
  }
  return readJson<T>(response)
}
