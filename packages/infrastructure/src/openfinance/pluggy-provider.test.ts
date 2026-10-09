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
          connector: {
            id: 7,
            name: 'Banco Exemplo',
            imageUrl: 'https://logo.example/7.svg',
            primaryColor: 'FF0000',
          },
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
      connector: {
        id: 7,
        name: 'Banco Exemplo',
        imageUrl: 'https://logo.example/7.svg',
        primaryColor: 'FF0000',
      },
    })
    expect(await pluggy.getItem('item-2')).toEqual({
      itemId: 'item-2',
      institutionName: 'Unknown institution',
      status: 'OUTDATED',
      lastUpdatedAt: null,
      connector: null,
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
              number: '0001/12345-6',
              balance: 1209.5,
              currencyCode: 'BRL',
            },
            {
              id: 'a2',
              type: 'CREDIT',
              subtype: 'CREDIT_CARD',
              name: 'Cartão',
              number: 'XXXX XXXX XXXX 4321',
              balance: 300,
              creditData: {
                brand: 'VISA',
                creditLimit: 5000,
                availableCreditLimit: 4700,
                balanceCloseDate: '2026-10-20T00:00:00.000Z',
                balanceDueDate: '2026-10-27T00:00:00',
              },
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
            {
              id: 'a4',
              type: 'CREDIT',
              number: 'card',
              creditData: { creditLimit: 100, balanceDueDate: 'soon' },
            },
            {
              id: 'a6',
              type: 'CREDIT',
              creditData: { availableCreditLimit: 1 },
            },
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
        numberSuffix: '3456',
        credit: null,
      },
      {
        externalId: 'a2',
        name: 'Cartão',
        type: 'CREDIT_CARD',
        balanceCents: -30000,
        currency: 'BRL',
        numberSuffix: '4321',
        credit: {
          limitCents: 500000,
          availableCents: 470000,
          closesOn: '2026-10-20',
          dueOn: '2026-10-27',
          brand: 'VISA',
        },
      },
      expect.objectContaining({ type: 'SAVINGS', balanceCents: 100 }),
      expect.objectContaining({
        type: 'CREDIT_CARD',
        name: 'Account',
        numberSuffix: null,
        credit: {
          limitCents: 10000,
          availableCents: 0,
          closesOn: null,
          dueOn: null,
          brand: null,
        },
      }),
      expect.objectContaining({ externalId: 'a6', credit: null }),
      expect.objectContaining({ type: 'CHECKING', numberSuffix: null }),
    ])
  })

  it('follows the transaction cursor and signs amounts by type', async () => {
    const first = `${PLUGGY_URL}/v2/transactions?accountId=a1&dateFrom=2026-10-01&dateTo=2026-10-31`
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
              merchant: { name: 'Mercado Exemplo' },
              creditCardMetadata: {
                installmentNumber: 3,
                totalInstallments: 10,
                purchaseDate: '2026-08-01T00:00:00.000Z',
              },
            },
            {
              id: 't2',
              amount: 12,
              type: 'DEBIT',
              currencyCode: 'USD',
              merchant: { businessName: 'Exemplo LTDA' },
              creditCardMetadata: {
                installmentNumber: 1,
                totalInstallments: 1,
              },
            },
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
        merchant: 'Mercado Exemplo',
        installment: { number: 3, count: 10, purchaseOn: '2026-08-01' },
        openBillCents: 0,
      },
      {
        externalId: 't2',
        accountExternalId: 'a1',
        amountCents: -1200,
        currency: 'USD',
        bookedOn: '',
        description: '',
        merchant: 'Exemplo LTDA',
        installment: null,
        openBillCents: 0,
      },
      expect.objectContaining({
        externalId: 't3',
        amountCents: 100000,
        bookedOn: '2026-10-05',
        merchant: null,
        installment: null,
        openBillCents: null,
      }),
    ])
  })

  it('counts pending unbilled charges and refunds toward the open bill', async () => {
    const url = `${PLUGGY_URL}/v2/transactions?accountId=a1&dateFrom=2026-10-01&dateTo=2026-10-31`
    const tx = (id: string, fields: object) => ({
      id,
      amount: 10,
      type: 'DEBIT',
      status: 'PENDING',
      creditCardMetadata: {},
      ...fields,
    })
    const scripted = new ScriptedTransport().on('GET', url, {
      json: {
        results: [
          tx('charge', {}),
          tx('abroad', { amount: 5, amountInAccountCurrency: 27.5 }),
          tx('billed', { creditCardMetadata: { billId: 'b1' } }),
          tx('posted', { status: 'POSTED' }),
          tx('refund', { type: 'CREDIT', operationType: 'ESTORNO' }),
          tx('payment', { type: 'CREDIT', amount: 900 }),
        ],
      },
    })
    const listed = await provider(scripted).listTransactions(connection, 'a1', {
      from: '2026-10-01',
      to: '2026-10-31',
    })
    expect(listed.map(t => t.openBillCents)).toEqual([
      -1000, -2750, 0, 0, 1000, 0,
    ])
  })

  it('keeps only real installments', async () => {
    const url = `${PLUGGY_URL}/v2/transactions?accountId=a1&dateFrom=2026-10-01&dateTo=2026-10-31`
    const tx = (id: string, metadata: object) => ({
      id,
      amount: 1,
      type: 'DEBIT',
      creditCardMetadata: metadata,
    })
    const scripted = new ScriptedTransport().on('GET', url, {
      json: {
        results: [
          tx('zero', { installmentNumber: 0, totalInstallments: 3 }),
          tx('over', { installmentNumber: 4, totalInstallments: 3 }),
          tx('half', { installmentNumber: 1.5, totalInstallments: 3 }),
          tx('none', {}),
          tx('ok', { installmentNumber: 2, totalInstallments: 3 }),
        ],
      },
    })
    const listed = await provider(scripted).listTransactions(connection, 'a1', {
      from: '2026-10-01',
      to: '2026-10-31',
    })
    expect(listed.map(t => t.installment)).toEqual([
      null,
      null,
      null,
      null,
      { number: 2, count: 3, purchaseOn: null },
    ])
  })

  it('lists card bills and the connectors with their logos', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${PLUGGY_URL}/bills?accountId=a2&page=1`, {
        json: {
          totalPages: 1,
          results: [
            {
              id: 'b1',
              dueDate: '2026-09-27T00:00:00',
              billClosingDate: '2026-09-20T00:00:00',
              totalAmount: 420.5,
              totalAmountCurrencyCode: 'BRL',
              minimumPaymentAmount: 50,
            },
            { id: 'b2', dueDate: '2026-08-27T00:00:00' },
            { id: 'b3' },
          ],
        },
      })
      .on('GET', `${PLUGGY_URL}/connectors?countries=BR&sandbox=false&page=1`, {
        json: {
          results: [
            { id: 1, name: 'Banco Exemplo', imageUrl: 'https://l.example/1' },
            { id: 2, name: 'Sem Logo', imageUrl: '', primaryColor: '' },
            { id: 3 },
            { name: 'No id' },
          ],
        },
      })
    const pluggy = provider(scripted)
    expect(await pluggy.listBills(connection, 'a2')).toEqual([
      {
        externalId: 'b1',
        closesOn: '2026-09-20',
        dueOn: '2026-09-27',
        totalCents: 42050,
        minimumCents: 5000,
        currency: 'BRL',
      },
      {
        externalId: 'b2',
        closesOn: null,
        dueOn: '2026-08-27',
        totalCents: 0,
        minimumCents: null,
        currency: 'BRL',
      },
    ])
    expect(await pluggy.listConnectors()).toEqual([
      {
        id: 1,
        name: 'Banco Exemplo',
        imageUrl: 'https://l.example/1',
        primaryColor: null,
      },
      { id: 2, name: 'Sem Logo', imageUrl: null, primaryColor: null },
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
