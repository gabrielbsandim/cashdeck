import { Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { NotFoundError } from '@/errors/errors'
import { type OpenFinanceProvider, type ProviderItem } from '@/ports/providers'
import { account, bill, fullDeps } from '@/testing/deps.test-helpers'
import { FakeOpenFinanceProvider } from '@/testing/providers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeOpenFinance } from '@/use-cases/open-finance'

const ITEM = '0b5c3a1e-7d2f-4c8a-9e61-3f2b8d4c5a10'

const item: ProviderItem = {
  itemId: ITEM,
  institutionName: 'Test Bank',
  status: 'UPDATED',
  lastUpdatedAt: null,
}

const provider = () =>
  new FakeOpenFinanceProvider(
    [
      {
        externalId: 'acc-1',
        name: 'Checking',
        type: 'CHECKING',
        balanceCents: 1000,
        currency: 'BRL',
      },
      {
        externalId: 'card-1',
        name: 'Card',
        type: 'CREDIT_CARD',
        balanceCents: -500,
        currency: 'BRL',
      },
    ],
    [
      {
        externalId: 'tx-1',
        accountExternalId: 'acc-1',
        amountCents: -300,
        currency: 'BRL',
        bookedOn: '2026-10-01',
        description: 'Market',
      },
      {
        externalId: 'tx-old',
        accountExternalId: 'acc-1',
        amountCents: -1,
        currency: 'BRL',
        bookedOn: '2025-09-01',
        description: 'Old',
      },
    ],
    [item],
  )

function setup(openFinance: OpenFinanceProvider = provider()) {
  const deps = fullDeps({ openFinance })
  return { deps, of: makeOpenFinance(deps) }
}

describe('open finance', () => {
  it('looks an item up, connects it and lists the connection', async () => {
    const { deps, of } = setup()
    const found = await of.lookup(TENANT, ITEM)
    expect(found).toMatchObject({ status: 'FOUND', institution: 'Test Bank' })
    const connected = await of.connect(TENANT, {
      itemId: ITEM,
      entity: 'PF',
      accountIds: ['acc-1', 'card-1'],
    })
    expect(connected.imported).toBe(2)
    expect(await of.lookup(TENANT, ITEM)).toEqual({
      status: 'ALREADY_CONNECTED',
      owner: 'PF',
    })
    const list = await of.list(TENANT)
    expect(list).toEqual([
      expect.objectContaining({
        institution: 'Test Bank',
        entityKind: 'PF',
        accountCount: 2,
        lastSyncAt: null,
      }),
    ])
    const card = (await deps.accounts.list(TENANT)).find(
      a => a.type === 'CREDIT_CARD',
    )
    expect(card?.balance.cents).toBe(-500)
  })

  it('answers NOT_FOUND for an unknown item and refuses to connect it', async () => {
    const missing = provider()
    missing.getItem = async () => {
      throw new NotFoundError('Item')
    }
    const { of } = setup(missing)
    expect(await of.lookup(TENANT, ITEM)).toEqual({ status: 'NOT_FOUND' })
    missing.getItem = async () => {
      throw Object.assign(new Error('Pluggy answered 404'), { status: 404 })
    }
    expect(await of.lookup(TENANT, ITEM)).toEqual({ status: 'NOT_FOUND' })
    await expect(
      of.connect(TENANT, { itemId: ITEM, entity: 'PF', accountIds: [] }),
    ).rejects.toThrow(NotFoundError)
  })

  it('passes other provider errors through', async () => {
    const { of } = setup(new FakeOpenFinanceProvider())
    await expect(of.lookup(TENANT, ITEM)).rejects.toThrow('was not found')
  })

  it('syncs balances and new transactions, then from the last sync', async () => {
    const { deps, of } = setup()
    const { connectionId } = await of.connect(TENANT, {
      itemId: ITEM,
      entity: 'PF',
      accountIds: ['acc-1'],
    })
    await deps.accounts.save(
      account({
        id: 'gone',
        entityId: 'pf',
        connectionId,
        externalId: 'closed',
      }),
    )
    await deps.bills.save(
      bill({ id: 'market', amount: Money.of(300), dueDate: '2026-10-02' }),
    )
    const first = await of.sync(TENANT, connectionId)
    expect(first).toEqual({
      accounts: 2,
      transactions: 1,
      settledBills: 1,
      syncedAt: NOW.toISOString(),
    })
    const second = await of.sync(TENANT, connectionId)
    expect(second.transactions).toBe(0)
    expect(await of.syncAll(TENANT)).toEqual({
      connections: 1,
      transactions: 0,
      failures: [],
    })
    expect((await of.list(TENANT))[0]?.lastSyncAt).toBe(NOW.toISOString())
  })

  it('collects sync failures and removes a connection', async () => {
    const base = provider()
    const flaky: OpenFinanceProvider = {
      getItem: itemId => base.getItem(itemId),
      listAccounts: async connection => {
        if (connection.itemId === 'x') {
          throw new Error('login error')
        }
        return base.listAccounts()
      },
      listTransactions: async () => [],
      listBills: async () => [],
      listConnectors: async () => [],
    }
    const { deps, of } = setup(flaky)
    const { connectionId } = await of.connect(TENANT, {
      itemId: ITEM,
      entity: 'PF',
      accountIds: ['acc-1'],
    })
    await deps.connections.save({
      id: 'broken',
      tenantId: TENANT,
      entityId: 'pf',
      institutionId: 'gone',
      provider: 'pluggy',
      itemId: 'x',
      status: 'LOGIN_ERROR',
      lastSyncAt: null,
    })
    const all = await of.syncAll(TENANT)
    expect(all.failures).toEqual([
      { connectionId: 'broken', reason: 'Error: login error' },
    ])
    expect(
      (await of.list(TENANT)).find(view => view.id === 'broken')?.institution,
    ).toBe('')
    expect(await of.remove(TENANT, connectionId)).toEqual({ id: connectionId })
    expect((await deps.accounts.list(TENANT))[0]).toMatchObject({
      connectionId: null,
      origin: 'MANUAL',
    })
    await expect(of.remove(TENANT, connectionId)).rejects.toThrow(NotFoundError)
    await expect(of.sync(TENANT, connectionId)).rejects.toThrow(NotFoundError)
  })

  it('names each aggregated account after its bank and keeps card details', async () => {
    const aggregated = new FakeOpenFinanceProvider(
      [
        {
          externalId: 'acc-1',
          name: 'BANCO EXEMPLO S.A.',
          type: 'CHECKING',
          balanceCents: 1000,
          currency: 'BRL',
          numberSuffix: '0001',
        },
        {
          externalId: 'card-1',
          name: 'PRODUTO CARTAO',
          type: 'CREDIT_CARD',
          balanceCents: -500,
          currency: 'BRL',
          numberSuffix: '4321',
          credit: {
            limitCents: 10_000,
            availableCents: 9_500,
            closesOn: '2026-10-20',
            dueOn: '2026-10-27',
            brand: 'VISA',
          },
        },
      ],
      [
        {
          externalId: 'tx-1',
          accountExternalId: 'card-1',
          amountCents: -300,
          currency: 'BRL',
          bookedOn: '2026-10-01',
          description: 'Loja 3/10',
          merchant: 'Loja Exemplo',
          installment: { number: 3, count: 10, purchaseOn: '2026-08-01' },
        },
      ],
      [
        {
          ...item,
          institutionName: 'MeuPluggy',
          connector: {
            id: 200,
            name: 'MeuPluggy',
            imageUrl: 'https://logo.example/meu.svg',
            primaryColor: '00AA00',
          },
        },
      ],
    )
    aggregated.connectors = [
      {
        id: 1,
        name: 'Banco Exemplo',
        imageUrl: 'https://logo.example/1.svg',
        primaryColor: 'FF0000',
      },
    ]
    aggregated.bills.set('card-1', [
      {
        externalId: 'bill-1',
        closesOn: '2026-09-20',
        dueOn: '2026-09-27',
        totalCents: 4_200,
        minimumCents: null,
        currency: 'BRL',
      },
      {
        externalId: 'bill-2',
        closesOn: null,
        dueOn: '2026-08-27',
        totalCents: 3_100,
        minimumCents: 500,
        currency: 'BRL',
      },
    ])
    const { deps, of } = setup(aggregated)
    const { connectionId } = await of.connect(TENANT, {
      itemId: ITEM,
      entity: 'PF',
      accountIds: ['acc-1', 'card-1'],
    })
    const stored = await deps.accounts.list(TENANT)
    const checking = stored.find(a => a.type === 'CHECKING')
    const card = stored.find(a => a.type === 'CREDIT_CARD')
    const bank = await deps.institutions.findById(
      TENANT,
      checking?.institutionId ?? '',
    )
    expect(bank).toMatchObject({
      name: 'Banco Exemplo',
      connectorId: 1,
      imageUrl: 'https://logo.example/1.svg',
    })
    const mirror = await deps.institutions.findById(
      TENANT,
      card?.institutionId ?? '',
    )
    expect(mirror).toMatchObject({ name: 'MeuPluggy', connectorId: 200 })
    expect(card).toMatchObject({
      numberSuffix: '4321',
      credit: { brand: 'VISA', dueOn: '2026-10-27', openBill: null },
    })
    expect(checking?.credit).toBeNull()

    const synced = await of.sync(TENANT, connectionId, { days: 400 })
    expect(synced.transactions).toBe(1)
    const [purchase] = await deps.transactions.all(TENANT, {})
    expect(purchase).toMatchObject({
      merchant: 'Loja Exemplo',
      installment: { number: 3, count: 10 },
    })
    const bills = await deps.cardBills.list(TENANT, [card?.id ?? ''])
    expect(bills.map(b => [b.dueOn, b.total.cents, b.minimum?.cents])).toEqual([
      ['2026-09-27', 4_200, undefined],
      ['2026-08-27', 3_100, 500],
    ])
  })

  it('sums the charges the issuer has not billed yet as the open bill', async () => {
    const card = {
      externalId: 'card-1',
      name: 'Card',
      type: 'CREDIT_CARD' as const,
      balanceCents: -9_000,
      currency: 'BRL',
      credit: {
        limitCents: 20_000,
        availableCents: 11_000,
        closesOn: null,
        dueOn: '2026-09-15',
        brand: null,
      },
    }
    const charge = (externalId: string, bookedOn: string, cents: number) => ({
      externalId,
      accountExternalId: 'card-1',
      amountCents: cents,
      currency: 'BRL',
      bookedOn,
      description: externalId,
    })
    const issuer = new FakeOpenFinanceProvider(
      [card],
      [
        { ...charge('installment', '2026-08-20', -300), openBillCents: -300 },
        { ...charge('billed', '2026-09-01', -200), openBillCents: 0 },
        { ...charge('refund', '2026-10-02', 50), openBillCents: 50 },
        { ...charge('payment', '2026-09-10', 9_000), openBillCents: 0 },
      ],
      [item],
    )
    const { deps, of } = setup(issuer)
    const { connectionId } = await of.connect(TENANT, {
      itemId: ITEM,
      entity: 'PF',
      accountIds: ['card-1'],
    })
    const synced = await of.sync(TENANT, connectionId)
    expect(synced.transactions).toBe(4)
    const [stored] = await deps.accounts.list(TENANT)
    expect(stored?.credit?.openBill?.cents).toBe(250)
    await of.sync(TENANT, connectionId)
    const [again] = await deps.accounts.list(TENANT)
    expect(again?.credit?.openBill?.cents).toBe(250)
  })

  it('keeps going when connectors, bills or the institution are missing', async () => {
    const base = provider()
    const broken: OpenFinanceProvider = {
      getItem: async () => ({ ...item, institutionName: 'MeuPluggy' }),
      listAccounts: () => base.listAccounts(),
      listTransactions: (...args) => base.listTransactions(...args),
      listBills: async () => {
        throw new Error('bills unavailable')
      },
      listConnectors: async () => {
        throw new Error('connectors unavailable')
      },
    }
    const { deps, of } = setup(broken)
    const { connectionId } = await of.connect(TENANT, {
      itemId: ITEM,
      entity: 'PF',
      accountIds: ['acc-1', 'card-1'],
    })
    const connection = await deps.connections.findById(TENANT, connectionId)
    const first = await of.sync(TENANT, connectionId)
    expect(first.accounts).toBe(2)
    await deps.connections.save({
      ...(connection as NonNullable<typeof connection>),
      institutionId: 'gone',
    })
    expect((await of.sync(TENANT, connectionId)).accounts).toBe(2)
    const card = (await deps.accounts.list(TENANT)).find(
      a => a.type === 'CREDIT_CARD',
    )
    await deps.accounts.save({
      ...(card as NonNullable<typeof card>),
      externalId: null,
    })
    expect((await of.sync(TENANT, connectionId)).accounts).toBe(2)
  })
})
