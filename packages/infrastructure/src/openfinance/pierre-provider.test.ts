import { ProviderNotConfiguredError } from '@cashdeck/application'
import { describe, expect, it } from 'vitest'
import { ProviderHttpError } from '@/http/transport'
import { PIERRE_URL, PierreProvider } from '@/openfinance/pierre-provider'
import { credentials } from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const range = { from: '2026-10-01', to: '2026-10-08' }

function provider(scripted: ScriptedTransport, key: string | null = 'sk-test') {
  return new PierreProvider({
    credentials: credentials(key ? { PIERRE_API_KEY: key } : {}),
    transport: scripted.transport,
  })
}

describe('PierreProvider', () => {
  it('lists the bank accounts with their type and balance', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${PIERRE_URL}/get-accounts`,
      {
        json: {
          data: [
            {
              id: 'pa-1',
              name: 'Banco Exemplo',
              type: 'BANK',
              subtype: 'CHECKING_ACCOUNT',
              balance: '120.50',
              connectorName: 'Banco Exemplo',
            },
            {
              id: 'pa-2',
              name: 'Gold',
              type: 'CREDIT',
              subtype: 'OTHER',
              balance: 80,
              connectorName: 'Banco Exemplo',
            },
            { id: 'pa-3', type: 'BANK', connectorName: 'Banco Exemplo' },
            { id: 'wallet', name: 'Wallet', type: 'BANK', connectorName: null },
          ],
        },
      },
    )
    expect(await provider(scripted).listAccounts()).toEqual([
      {
        externalId: 'pa-1',
        institutionName: 'Banco Exemplo',
        name: 'Banco Exemplo',
        type: 'CHECKING',
        balanceCents: 12050,
      },
      {
        externalId: 'pa-2',
        institutionName: 'Banco Exemplo',
        name: 'Gold',
        type: 'CREDIT_CARD',
        balanceCents: -8000,
      },
      {
        externalId: 'pa-3',
        institutionName: 'Banco Exemplo',
        name: '',
        type: 'CHECKING',
        balanceCents: 0,
      },
    ])
    expect(
      scripted.last('GET', `${PIERRE_URL}/get-accounts`).headers,
    ).toMatchObject({ authorization: 'Bearer sk-test' })
  })

  it('reads bank and card movements in the range', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${PIERRE_URL}/get-transactions?accountType=BANK`, {
        json: {
          data: [
            {
              id: '1',
              account_id: 'pa-1',
              description: 'PIX ENVIADO',
              amount: 25.5,
              currency_code: 'BRL',
              date: '2026-10-07T21:15:00.000Z',
              type: 'DEBIT',
              payment_data: {
                receiver: { documentNumber: { value: '111.444.777-35' } },
              },
            },
            {
              id: '2',
              account_id: 'pa-1',
              description: '',
              amount: 100,
              date: '2026-10-06T12:00:00.000Z',
              type: 'CREDIT',
              merchant: { businessName: 'Empresa Exemplo' },
              payment_data: {
                payer: { documentNumber: { value: '11.444.777/0001-61' } },
              },
            },
            { id: 'broken', amount: 1 },
          ],
        },
      })
      .on('GET', `${PIERRE_URL}/get-transactions?accountType=CREDIT`, {
        json: {
          data: [
            {
              id: '3',
              account_id: 'pa-2',
              description: 'LOJA EXEMPLO',
              amount: 300,
              date: '2026-10-05T15:00:00.000Z',
              type: 'DEBIT',
              merchant: { name: 'Loja Exemplo' },
              credit_card_data: {
                installmentNumber: 2,
                totalInstallments: 3,
                purchaseDate: '2026-08-05T00:00:00.000Z',
              },
            },
          ],
        },
      })
    const movements = await provider(scripted).listTransactions(range)
    expect(movements).toEqual([
      {
        externalId: 'pierre:1',
        accountExternalId: 'pa-1',
        amountCents: -2550,
        currency: 'BRL',
        bookedOn: '2026-10-07',
        description: 'PIX ENVIADO',
        merchant: null,
        counterparty: '111.444.777-35',
        installment: null,
      },
      {
        externalId: 'pierre:2',
        accountExternalId: 'pa-1',
        amountCents: 10000,
        currency: 'BRL',
        bookedOn: '2026-10-06',
        description: 'Transaction',
        merchant: 'Empresa Exemplo',
        counterparty: '11.444.777/0001-61',
        installment: null,
      },
      {
        externalId: 'pierre:3',
        accountExternalId: 'pa-2',
        amountCents: -30000,
        currency: 'BRL',
        bookedOn: '2026-10-05',
        description: 'LOJA EXEMPLO',
        merchant: 'Loja Exemplo',
        counterparty: null,
        installment: { number: 2, count: 3, purchaseOn: '2026-08-05' },
      },
    ])
    expect(scripted.last('GET', `${PIERRE_URL}/get-transactions`).url).toBe(
      `${PIERRE_URL}/get-transactions?accountType=CREDIT&startDate=2026-10-01&endDate=2026-10-08&format=raw`,
    )
  })

  it('asks for a refresh and reports a failed or unconfigured call', async () => {
    const scripted = new ScriptedTransport()
      .on('POST', `${PIERRE_URL}/manual-update`, { json: { success: true } })
      .on('GET', `${PIERRE_URL}/get-accounts`, { status: 401, json: {} })
      .on('GET', `${PIERRE_URL}/get-transactions`, { json: {} })
    const pierre = provider(scripted)
    await pierre.requestRefresh()
    expect(scripted.requests[0]?.method).toBe('POST')
    await expect(pierre.listAccounts()).rejects.toBeInstanceOf(
      ProviderHttpError,
    )
    expect(await pierre.listTransactions(range)).toEqual([])
    await expect(
      provider(new ScriptedTransport(), null).listAccounts(),
    ).rejects.toBeInstanceOf(ProviderNotConfiguredError)
  })

  it('reads an answer without data as empty', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${PIERRE_URL}/get-accounts`,
      { json: {} },
    )
    expect(await provider(scripted).listAccounts()).toEqual([])
  })
})
