import { describe, expect, it } from 'vitest'
import { PLUGGY_URL, PluggyProvider } from '@/openfinance/pluggy-provider'
import { credentials } from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const connection = { provider: 'pluggy', itemId: 'item-1' }

function provider(scripted: ScriptedTransport) {
  scripted.on('POST', `${PLUGGY_URL}/auth`, { json: { apiKey: 'api-key' } })
  return new PluggyProvider({
    credentials: credentials({
      PLUGGY_CLIENT_ID: 'id',
      PLUGGY_CLIENT_SECRET: 'secret',
    }),
    transport: scripted.transport,
    pageSize: 2,
  })
}

describe('PluggyProvider', () => {
  it('reads an item by the id copied from the dashboard', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${PLUGGY_URL}/items/item-1`, {
        json: {
          id: 'item-1',
          status: 'UPDATED',
          lastUpdatedAt: '2026-10-08T09:00:00.000Z',
          connector: { name: 'Banco Exemplo' },
        },
      })
      .on('GET', `${PLUGGY_URL}/items/item-2`, {
        json: { id: 'item-2', status: 'SOMETHING_NEW' },
      })
    const pluggy = provider(scripted)
    expect(await pluggy.getItem('item-1')).toEqual({
      itemId: 'item-1',
      institutionName: 'Banco Exemplo',
      status: 'UPDATED',
      lastUpdatedAt: '2026-10-08T09:00:00.000Z',
    })
    expect(await pluggy.getItem('item-2')).toEqual({
      itemId: 'item-2',
      institutionName: 'Unknown institution',
      status: 'OUTDATED',
      lastUpdatedAt: null,
    })
    expect(scripted.body('POST', `${PLUGGY_URL}/auth`)).toEqual({
      clientId: 'id',
      clientSecret: 'secret',
    })
    expect(
      scripted.last('GET', `${PLUGGY_URL}/items/item-1`).headers,
    ).toMatchObject({ 'x-api-key': 'api-key' })
    expect(
      scripted.requests.filter(r => r.url === `${PLUGGY_URL}/auth`),
    ).toHaveLength(1)
  })

  it('lists accounts across pages and maps their types', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${PLUGGY_URL}/accounts?itemId=item-1&page=1`, {
        json: {
          page: 1,
          totalPages: 2,
          results: [
            {
              id: 'a1',
              type: 'BANK',
              subtype: 'CHECKING_ACCOUNT',
              name: 'Conta Corrente',
              balance: 1209.5,
              currencyCode: 'BRL',
            },
            {
              id: 'a2',
              type: 'CREDIT',
              subtype: 'CREDIT_CARD',
              name: 'Cartão',
              balance: 300,
            },
          ],
        },
      })
      .on('GET', `${PLUGGY_URL}/accounts?itemId=item-1&page=2`, {
        json: {
          page: 2,
          totalPages: 2,
          results: [
            { id: 'a3', type: 'BANK', subtype: 'SAVINGS_ACCOUNT', balance: 1 },
            { id: 'a4', type: 'CREDIT' },
            { id: 'a5', type: 'BANK', subtype: 'OTHER' },
          ],
        },
      })
    const accounts = await provider(scripted).listAccounts(connection)
    expect(accounts).toEqual([
      {
        externalId: 'a1',
        name: 'Conta Corrente',
        type: 'CHECKING',
        balanceCents: 120950,
        currency: 'BRL',
      },
      {
        externalId: 'a2',
        name: 'Cartão',
        type: 'CREDIT_CARD',
        balanceCents: -30000,
        currency: 'BRL',
      },
      expect.objectContaining({ type: 'SAVINGS', balanceCents: 100 }),
      expect.objectContaining({ type: 'CREDIT_CARD', name: 'Account' }),
      expect.objectContaining({ type: 'CHECKING' }),
    ])
  })

  it('follows the transaction cursor and signs amounts by type', async () => {
    const first = `${PLUGGY_URL}/v2/transactions?accountId=a1&dateFrom=2026-10-01&dateTo=2026-10-31&pageSize=2`
    const scripted = new ScriptedTransport()
      .on('GET', `${first}&after=cursor-2`, {
        json: {
          results: [
            {
              id: 't3',
              amount: 1000,
              type: 'CREDIT',
              date: '2026-10-05T03:00:00.000Z',
            },
          ],
          next: 'cursor-3',
        },
      })
      .on('GET', `${first}&after=cursor-3`, { json: { next: null } })
      .on('GET', first, {
        json: {
          results: [
            {
              id: 't1',
              accountId: 'a1',
              description: 'Mercado',
              amount: -45.9,
              type: 'DEBIT',
              date: '2026-10-02T03:00:00.000Z',
              currencyCode: 'BRL',
            },
            { id: 't2', amount: 12, type: 'DEBIT', currencyCode: 'USD' },
          ],
          next: `${PLUGGY_URL}/v2/transactions?accountId=a1&after=cursor-2`,
        },
      })
    const transactions = await provider(scripted).listTransactions(
      connection,
      'a1',
      { from: '2026-10-01', to: '2026-10-31' },
    )
    expect(transactions).toEqual([
      {
        externalId: 't1',
        accountExternalId: 'a1',
        amountCents: -4590,
        currency: 'BRL',
        bookedOn: '2026-10-02',
        description: 'Mercado',
      },
      {
        externalId: 't2',
        accountExternalId: 'a1',
        amountCents: -1200,
        currency: 'USD',
        bookedOn: '',
        description: '',
      },
      expect.objectContaining({
        externalId: 't3',
        amountCents: 100000,
        bookedOn: '2026-10-05',
      }),
    ])
  })

  it('authenticates again when the api key expires', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${PLUGGY_URL}/items/item-1`,
      { status: 401 },
      { json: { id: 'item-1', status: 'UPDATING' } },
    )
    expect((await provider(scripted).getItem('item-1')).status).toBe('UPDATING')
    expect(
      scripted.requests.filter(r => r.url === `${PLUGGY_URL}/auth`),
    ).toHaveLength(2)
  })

  it('reports errors and missing credentials', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${PLUGGY_URL}/items/x`,
      { status: 404, text: 'not found' },
    )
    await expect(provider(scripted).getItem('x')).rejects.toThrow(
      'Pluggy answered 404',
    )
    const noKey = new ScriptedTransport().on('POST', `${PLUGGY_URL}/auth`, {
      json: {},
    })
    const broken = new PluggyProvider({
      credentials: credentials({
        PLUGGY_CLIENT_ID: 'id',
        PLUGGY_CLIENT_SECRET: 'secret',
      }),
      transport: noKey.transport,
    })
    await expect(broken.getItem('x')).rejects.toThrow('no apiKey')
    const unconfigured = new PluggyProvider({
      credentials: credentials({}),
      transport: new ScriptedTransport().transport,
    })
    await expect(unconfigured.getItem('x')).rejects.toThrow(
      'Pluggy is not configured.',
    )
  })
})
