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
        bookedOn: '2026-01-01',
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
})
