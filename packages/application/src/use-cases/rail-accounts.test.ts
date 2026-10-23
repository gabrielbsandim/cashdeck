import { describe, expect, it } from 'vitest'
import { createAccount, Money } from '@cashdeck/domain'
import { ProviderNotConfiguredError } from '@/errors/errors'
import { type ProviderAccount } from '@/ports/providers'
import { fullDeps } from '@/testing/deps.test-helpers'
import { FakeOpenFinanceProvider } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeOpenFinance } from '@/use-cases/open-finance'
import {
  entityOfRailItem,
  isRailAccountItem,
  makeRailAccounts,
  railAccountItemId,
} from '@/use-cases/rail-accounts'

const ITEM = railAccountItemId('pf')

const remote = (overrides: Partial<ProviderAccount> = {}): ProviderAccount => ({
  externalId: ITEM,
  name: 'Asaas',
  type: 'CHECKING',
  balanceCents: 199_700,
  currency: 'BRL',
  numberSuffix: '8762',
  ...overrides,
})

function setup(
  accounts: ProviderAccount[] = [remote()],
  enabledRails: Array<'ASAAS' | 'INTER_EMPRESAS'> = ['ASAAS'],
) {
  const provider = new FakeOpenFinanceProvider(
    accounts,
    [
      {
        externalId: 'asaas:ftn_1',
        accountExternalId: ITEM,
        amountCents: 198_000,
        currency: 'BRL',
        bookedOn: '2026-10-08',
        description: 'Cobrança recebida',
      },
    ],
    [
      {
        itemId: ITEM,
        institutionName: 'Asaas',
        status: 'UPDATED',
        lastUpdatedAt: null,
      },
    ],
  )
  const deps = fullDeps({ openFinance: provider, settings: { enabledRails } })
  const openFinance = makeOpenFinance(deps)
  return { deps, railAccounts: makeRailAccounts(deps, openFinance.sync) }
}

describe('rail accounts', () => {
  it('names the entity in the item id', () => {
    expect(ITEM).toBe('asaas:pf')
    expect(isRailAccountItem(ITEM)).toBe(true)
    expect(isRailAccountItem('3f2c0a4e-0000-4000-8000-000000000000')).toBe(
      false,
    )
    expect(entityOfRailItem(ITEM)).toBe('pf')
  })

  it('opens the account once for the entity the rail pays for', async () => {
    const { deps, railAccounts } = setup()
    expect(await railAccounts.sync(TENANT)).toEqual({
      accounts: 1,
      transactions: 1,
      failures: [],
    })
    await railAccounts.sync(TENANT)
    const connections = await deps.connections.list(TENANT)
    expect(connections).toMatchObject([
      { entityId: 'pf', provider: 'asaas', itemId: ITEM, status: 'UPDATED' },
    ])
    const [account] = await deps.accounts.list(TENANT)
    expect(account).toMatchObject({
      entityId: 'pf',
      name: 'Asaas',
      origin: 'CONNECTED',
      isReserve: true,
      numberSuffix: '8762',
      connectionId: connections[0]?.id,
    })
    expect(account?.balance.cents).toBe(199_700)
    const institution = await deps.institutions.findById(
      TENANT,
      account?.institutionId as string,
    )
    expect(institution?.name).toBe('Asaas')
    expect(institution?.imageUrl).toBe(
      'https://www.asaas.com/staticboto/apple-touch-icon.png',
    )
    expect(await deps.transactions.all(TENANT, {})).toHaveLength(1)
  })

  it('leaves the reserve the user already chose', async () => {
    const { deps, railAccounts } = setup([remote({ numberSuffix: undefined })])
    await deps.accounts.save(
      createAccount({
        id: 'savings',
        tenantId: TENANT,
        entityId: 'pf',
        institutionId: 'bank',
        name: 'Savings',
        type: 'SAVINGS',
        origin: 'MANUAL',
        isReserve: true,
        balance: Money.zero(),
      }),
    )
    await railAccounts.sync(TENANT)
    const asaas = (await deps.accounts.list(TENANT)).find(
      account => account.name === 'Asaas',
    )
    expect(asaas).toMatchObject({ isReserve: false, numberSuffix: null })
  })

  it('skips entities that do not pay through the rail', async () => {
    const { deps, railAccounts } = setup([remote()], ['INTER_EMPRESAS'])
    expect(await railAccounts.sync(TENANT)).toEqual({
      accounts: 0,
      transactions: 0,
      failures: [],
    })
    expect(await deps.connections.list(TENANT)).toEqual([])
  })

  it('reports a failed sync or setup without throwing', async () => {
    const { deps, railAccounts } = setup()
    deps.openFinance.listTransactions = async () => {
      throw new Error('statement down')
    }
    expect(await railAccounts.sync(TENANT)).toEqual({
      accounts: 0,
      transactions: 0,
      failures: [{ entityId: 'pf', reason: 'Error: statement down' }],
    })
    const broken = setup()
    broken.deps.openFinance.listAccounts = async () => {
      throw new Error('refused')
    }
    expect(await broken.railAccounts.sync(TENANT)).toEqual({
      accounts: 0,
      transactions: 0,
      failures: [{ entityId: 'pf', reason: 'Error: refused' }],
    })
  })

  it('waits quietly for the rail credentials', async () => {
    const { deps, railAccounts } = setup()
    deps.openFinance.listAccounts = async () => {
      throw new ProviderNotConfiguredError('Asaas')
    }
    expect(await railAccounts.sync(TENANT)).toEqual({
      accounts: 0,
      transactions: 0,
      failures: [],
    })
    expect(await deps.connections.list(TENANT)).toEqual([])
  })
})
