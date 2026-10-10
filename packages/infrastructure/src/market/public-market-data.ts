import { type DailyValue, type MarketData } from '@cashdeck/application'
import { addDays, type LocalDate, toLocalDate } from '@cashdeck/domain'
import {
  type HttpResponse,
  isSuccess,
  ProviderHttpError,
  readJson,
  send,
  type Transport,
} from '@/http/transport'

export const YAHOO_CHART_URL =
  'https://query1.finance.yahoo.com/v8/finance/chart'
export const BCB_CDI_URL =
  'https://api.bcb.gov.br/dados/serie/bcdata.sgs.12/dados'

// Yahoo turns away clients that do not look like a browser.
const BROWSER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'

type YahooChart = {
  chart?: {
    result?: Array<{
      timestamp?: number[] | null
      indicators?: { quote?: Array<{ close?: Array<number | null> | null }> }
    }> | null
  }
}

type SgsRow = { data?: string; valor?: string }

const startOf = (day: LocalDate) =>
  Math.floor(Date.parse(`${day}T00:00:00-03:00`) / 1000)

const brazilianDate = (day: LocalDate) => day.split('-').reverse().join('/')

function isoDay(value: string | undefined): LocalDate | null {
  const match = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value ?? '')
  return match ? `${match[3]}-${match[2]}-${match[1]}` : null
}

export type PublicMarketDataDeps = { transport: Transport }

// Quotes from Yahoo Finance and the CDI from the central bank's SGS series
// 12, both public and keyless.
export class PublicMarketData implements MarketData {
  constructor(private readonly deps: PublicMarketDataDeps) {}

  async dailyCloses(
    ticker: string,
    from: LocalDate,
    to: LocalDate,
  ): Promise<DailyValue[]> {
    const query = new URLSearchParams({
      period1: String(startOf(from)),
      period2: String(startOf(addDays(to, 1))),
      interval: '1d',
    })
    const response = await send(this.deps.transport, {
      method: 'GET',
      url: `${YAHOO_CHART_URL}/${encodeURIComponent(`${ticker}.SA`)}?${query.toString()}`,
      headers: { 'user-agent': BROWSER_AGENT },
    })
    const result = parse<YahooChart>('Yahoo Finance', response).chart
      ?.result?.[0]
    const closes = result?.indicators?.quote?.[0]?.close ?? []
    return (result?.timestamp ?? []).flatMap((seconds, index) => {
      const close = closes[index]
      return typeof close === 'number'
        ? [{ day: toLocalDate(new Date(seconds * 1000)), value: close }]
        : []
    })
  }

  async cdiRates(from: LocalDate, to: LocalDate): Promise<DailyValue[]> {
    const query = new URLSearchParams({
      formato: 'json',
      dataInicial: brazilianDate(from),
      dataFinal: brazilianDate(to),
    })
    const response = await send(this.deps.transport, {
      method: 'GET',
      url: `${BCB_CDI_URL}?${query.toString()}`,
    })
    // SGS answers 404 for a range with no rate published, such as a weekend.
    if (response.status === 404) {
      return []
    }
    return parse<SgsRow[]>('Banco Central', response).flatMap(row => {
      const day = isoDay(row.data)
      const value = Number(row.valor)
      return day && Number.isFinite(value) ? [{ day, value }] : []
    })
  }
}

function parse<T>(provider: string, response: HttpResponse): T {
  if (!isSuccess(response)) {
    throw new ProviderHttpError(provider, response.status, response.text)
  }
  return readJson<T>(response)
}
