import {
  NotFoundError,
  type OpenFinanceProvider,
  ProviderNotConfiguredError,
} from '@cashdeck/application'
import { describe, expect, it } from 'vitest'
import { ProviderHttpError } from '@/http/transport'
import {
  AsaasStatementProvider,
  RailAccountRouter,
} from '@/openfinance/asaas-statement-provider'
import { ASAAS_URLS } from '@/rails/asaas-rail'
import { credentials } from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const BASE = ASAAS_URLS.production
const ITEM = 'asaas:pf'
const link = { provider: 'asaas', itemId: ITEM }
const range = { from: '2026-10-01', to: '2026-10-15' }

function provider(
  scripted: ScriptedTransport,
  env: Record<string, string> = { ASAAS_API_KEY: 'key-test' },
) {
  return new AsaasStatementProvider({
    credentials: credentials(env),
    transport: scripted.transport,
  })
}

describe('AsaasStatementProvider', () => {
  it('answers only for its own items', async () => {
    const asaas = provider(new ScriptedTransport())
    expect(await asaas.getItem(ITEM)).toEqual({
      itemId: ITEM,
      institutionName: 'Asaas',
      status: 'UPDATED',
      lastUpdatedAt: null,
    })
    await expect(asaas.getItem('item-1')).rejects.toThrow(NotFoundError)
    expect(await asaas.listBills()).toEqual([])
    expect(await asaas.listConnectors()).toEqual([])
    expect(await asaas.listInvestments()).toEqual([])
    expect(await asaas.listInvestmentMovements()).toEqual([])
  })

  it('reads the balance and the account number as one checking account', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${BASE}/finance/balance`, { json: { balance: 1997.5 } })
      .on('GET', `${BASE}/myAccount/accountNumber`, {
        json: { agency: '0001', account: '1234567', accountDigit: '8' },
      })
    expect(await provider(scripted).listAccounts(link)).toEqual([
      {
        externalId: ITEM,
        name: 'Asaas',
        type: 'CHECKING',
        balanceCents: 199_750,
        currency: 'BRL',
        numberSuffix: '5678',
      },
    ])
    expect(scripted.last('GET', `${BASE}/finance/balance`).headers).toEqual({
      accept: 'application/json',
      access_token: 'key-test',
      'user-agent': 'cashdeck',
    })
  })

  it('keeps the account when its number cannot be read', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${BASE}/finance/balance`, { json: {} })
      .on('GET', `${BASE}/myAccount/accountNumber`, { status: 403 })
    const [account] = await provider(scripted).listAccounts(link)
    expect(account).toMatchObject({ balanceCents: 0, numberSuffix: null })
    const empty = new ScriptedTransport()
      .on('GET', `${BASE}/finance/balance`, { json: { balance: 1 } })
      .on('GET', `${BASE}/myAccount/accountNumber`, { json: {} })
    const [unnumbered] = await provider(empty).listAccounts(link)
    expect(unnumbered?.numberSuffix).toBeNull()
  })

  it('pages through the statement and signs each entry', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${BASE}/financialTransactions`,
      {
        json: {
          hasMore: true,
          data: [
            {
              id: 'ftn_1',
              value: 1980,
              date: '2026-10-15',
              description: 'Cobrança recebida ',
            },
            { id: 'ftn_2', value: -2, date: '2026-10-15', description: null },
          ],
        },
      },
      {
        json: {
          hasMore: false,
          data: [
            { id: 'ftn_3', value: -1, date: '2026-10-14', description: '' },
            { id: 'ftn_4', date: '2026-10-14' },
            { id: 'ftn_5', value: 3 },
          ],
        },
      },
    )
    expect(
      await provider(scripted).listTransactions(link, ITEM, range),
    ).toEqual([
      {
        externalId: 'asaas:ftn_1',
        accountExternalId: ITEM,
        amountCents: 198_000,
        currency: 'BRL',
        bookedOn: '2026-10-15',
        description: 'Cobrança recebida',
      },
      {
        externalId: 'asaas:ftn_2',
        accountExternalId: ITEM,
        amountCents: -200,
        currency: 'BRL',
        bookedOn: '2026-10-15',
        description: 'Asaas',
      },
      {
        externalId: 'asaas:ftn_3',
        accountExternalId: ITEM,
        amountCents: -100,
        currency: 'BRL',
        bookedOn: '2026-10-14',
        description: 'Asaas',
      },
    ])
    const urls = scripted.requests.map(request => new URL(request.url))
    expect(urls.map(url => url.searchParams.get('offset'))).toEqual([
      '0',
      '100',
    ])
    expect(Object.fromEntries(urls[0]?.searchParams ?? [])).toEqual({
      startDate: '2026-10-01',
      finishDate: '2026-10-15',
      offset: '0',
      limit: '100',
    })
  })

  it('reads the sandbox with the credentials of the entity', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${ASAAS_URLS.sandbox}/financialTransactions`,
      { json: {} },
    )
    const scopes: unknown[] = []
    const asaas = new AsaasStatementProvider({
      credentials: {
        get: async (name, scope) => {
          scopes.push(scope)
          return name === 'ASAAS_API_KEY' ? 'key-pf' : 'sandbox'
        },
      },
      transport: scripted.transport,
    })
    expect(await asaas.listTransactions(link, ITEM, range)).toEqual([])
    expect(
      scripted.last('GET', `${ASAAS_URLS.sandbox}/financialTransactions`)
        .headers?.access_token,
    ).toBe('key-pf')
    expect(scopes).toEqual([{ entityId: 'pf' }, { entityId: 'pf' }])
  })

  it('fails loudly on a refused call or a missing key', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${BASE}/finance/balance`,
      { status: 401, text: 'unauthorized' },
    )
    await expect(provider(scripted).listAccounts(link)).rejects.toThrow(
      ProviderHttpError,
    )
    await expect(
      provider(new ScriptedTransport(), {}).listAccounts(link),
    ).rejects.toThrow(ProviderNotConfiguredError)
  })
})

describe('RailAccountRouter', () => {
  const recorder = (name: string, calls: string[]): OpenFinanceProvider => ({
    getItem: async itemId => {
      calls.push(`${name}:getItem:${itemId}`)
      return {
        itemId,
        institutionName: name,
        status: 'UPDATED',
        lastUpdatedAt: null,
      }
    },
    listAccounts: async () => {
      calls.push(`${name}:listAccounts`)
      return []
    },
    listTransactions: async () => {
      calls.push(`${name}:listTransactions`)
      return []
    },
    listBills: async () => {
      calls.push(`${name}:listBills`)
      return []
    },
    listConnectors: async () => {
      calls.push(`${name}:listConnectors`)
      return []
    },
    listInvestments: async () => {
      calls.push(`${name}:listInvestments`)
      return []
    },
    listInvestmentMovements: async () => {
      calls.push(`${name}:listInvestmentMovements`)
      return []
    },
  })

  it('sends Asaas items to the statement and the rest to the banks', async () => {
    const calls: string[] = []
    const router = new RailAccountRouter(
      recorder('banks', calls),
      recorder('asaas', calls),
    )
    const bank = { provider: 'pluggy', itemId: 'item-1' }
    for (const connection of [bank, link]) {
      await router.getItem(connection.itemId)
      await router.listAccounts(connection)
      await router.listTransactions(connection, 'acc', range)
      await router.listBills(connection, 'acc')
      await router.listInvestments(connection)
      await router.listInvestmentMovements(connection, 'inv')
    }
    await router.listConnectors()
    expect(calls).toEqual([
      'banks:getItem:item-1',
      'banks:listAccounts',
      'banks:listTransactions',
      'banks:listBills',
      'banks:listInvestments',
      'banks:listInvestmentMovements',
      `asaas:getItem:${ITEM}`,
      'asaas:listAccounts',
      'asaas:listTransactions',
      'asaas:listBills',
      'asaas:listInvestments',
      'asaas:listInvestmentMovements',
      'banks:listConnectors',
    ])
  })
})
