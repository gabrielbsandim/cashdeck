import {
  type FipeVehicle,
  NotFoundError,
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
