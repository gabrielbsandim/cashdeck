import { describe, expect, it } from 'vitest'
import {
  BCB_CDI_URL,
  PublicMarketData,
  YAHOO_CHART_URL,
} from '@/market/public-market-data'
import { ScriptedTransport } from '@/testing/scripted-transport'

const opening = (day: string) => Date.parse(`${day}T13:00:00Z`) / 1000

describe('PublicMarketData', () => {
  it('reads daily closes of a B3 ticker and skips days without one', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${YAHOO_CHART_URL}/ABCD11.SA?`,
      {
        json: {
          chart: {
            result: [
              {
                timestamp: [
                  opening('2026-10-05'),
                  opening('2026-10-06'),
                  opening('2026-10-07'),
                ],
                indicators: { quote: [{ close: [104.5, null, 105.25] }] },
              },
            ],
          },
        },
      },
    )
    const market = new PublicMarketData({ transport: scripted.transport })
    expect(
      await market.dailyCloses('ABCD11', '2026-10-05', '2026-10-07'),
    ).toEqual([
      { day: '2026-10-05', value: 104.5 },
      { day: '2026-10-07', value: 105.25 },
    ])
    const request = scripted.last('GET', `${YAHOO_CHART_URL}/ABCD11.SA`)
    expect(new URL(request.url).searchParams.get('period1')).toBe(
      String(Date.parse('2026-10-05T03:00:00Z') / 1000),
    )
    expect(new URL(request.url).searchParams.get('period2')).toBe(
      String(Date.parse('2026-10-08T03:00:00Z') / 1000),
    )
    expect(request.headers?.['user-agent']).toMatch(/^Mozilla/)
  })

  it('reads an empty chart as no closes and a refusal as an error', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${YAHOO_CHART_URL}/NONE11.SA?`, {
        json: { chart: { result: null } },
      })
      .on('GET', `${YAHOO_CHART_URL}/WXYZ3.SA?`, {
        json: { chart: { result: [{ timestamp: [opening('2026-10-05')] }] } },
      })
      .on('GET', `${YAHOO_CHART_URL}/BUSY3.SA?`, {
        status: 429,
        text: 'Too Many Requests',
      })
    const market = new PublicMarketData({ transport: scripted.transport })
    expect(
      await market.dailyCloses('NONE11', '2026-10-01', '2026-10-07'),
    ).toEqual([])
    expect(
      await market.dailyCloses('WXYZ3', '2026-10-01', '2026-10-07'),
    ).toEqual([])
    await expect(
      market.dailyCloses('BUSY3', '2026-10-01', '2026-10-07'),
    ).rejects.toThrow('Yahoo Finance answered 429')
  })

  it('reads the daily CDI in Brazilian dates and an empty range as none', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${BCB_CDI_URL}?formato=json&dataInicial=01%2F10%2F2026`, {
        json: [
          { data: '01/10/2026', valor: '0.050788' },
          { data: '02/10/2026', valor: 'n/a' },
          { data: '2026-10-05', valor: '0.050788' },
          { data: '05/10/2026', valor: '0.051' },
        ],
      })
      .on('GET', `${BCB_CDI_URL}?formato=json&dataInicial=03%2F10%2F2026`, {
        status: 404,
        json: { erro: { statusCode: 404, detail: 'Value(s) not found' } },
      })
      .on('GET', `${BCB_CDI_URL}?formato=json&dataInicial=06%2F10%2F2026`, {
        status: 500,
        text: 'down',
      })
    const market = new PublicMarketData({ transport: scripted.transport })
    expect(await market.cdiRates('2026-10-01', '2026-10-05')).toEqual([
      { day: '2026-10-01', value: 0.050788 },
      { day: '2026-10-05', value: 0.051 },
    ])
    expect(
      scripted
        .last('GET', BCB_CDI_URL)
        .url.endsWith('dataFinal=05%2F10%2F2026'),
    ).toBe(true)
    expect(await market.cdiRates('2026-10-03', '2026-10-04')).toEqual([])
    await expect(market.cdiRates('2026-10-06', '2026-10-07')).rejects.toThrow(
      'Banco Central answered 500',
    )
  })
})
