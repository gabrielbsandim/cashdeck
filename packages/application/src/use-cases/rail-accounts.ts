import {
  CASH_ACCOUNT_TYPES,
  createAccount,
  type FinancialEntity,
  Money,
  type RailId,
  routesThrough,
} from '@cashdeck/domain'
import { ProviderNotConfiguredError } from '@/errors/errors'
import { type Connection } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'

// A payment rail that holds money is read like a bank: its connection goes
// through the Open Finance provider, which routes this item id to the rail.
export const RAIL_ACCOUNT_PROVIDER = 'asaas'
const RAIL: RailId = 'ASAAS'
const INSTITUTION = 'Asaas'

export const railAccountItemId = (entityId: string) =>
  `${RAIL_ACCOUNT_PROVIDER}:${entityId}`

export const isRailAccountItem = (itemId: string) =>
  itemId.startsWith(`${RAIL_ACCOUNT_PROVIDER}:`)

export const entityOfRailItem = (itemId: string) =>
  itemId.slice(RAIL_ACCOUNT_PROVIDER.length + 1)

type RailAccountDeps = Pick<
  Deps,
  | 'entities'
  | 'settings'
  | 'connections'
  | 'institutions'
  | 'accounts'
  | 'openFinance'
  | 'ids'
>

type SyncConnection = (
  tenantId: string,
  connectionId: string,
) => Promise<{ transactions: number }>

export function makeRailAccounts(
  deps: RailAccountDeps,
  syncConnection: SyncConnection,
) {
  async function connect(tenantId: string, entityId: string) {
    const itemId = railAccountItemId(entityId)
    const institution = await deps.institutions.ensure({
      id: deps.ids.next(),
      tenantId,
      name: INSTITUTION,
      manual: false,
    })
    const connection: Connection = {
      id: deps.ids.next(),
      tenantId,
      entityId,
      institutionId: institution.id,
      provider: RAIL_ACCOUNT_PROVIDER,
      itemId,
      status: 'UPDATED',
      lastSyncAt: null,
    }
    const offered = await deps.openFinance.listAccounts({
      provider: RAIL_ACCOUNT_PROVIDER,
      itemId,
    })
    await deps.connections.save(connection)
    // The rail is where bills are paid from, so it is the reserve unless the
    // user already chose one.
    const owned = await deps.accounts.listByEntity(tenantId, entityId)
    const reserve = owned.some(account => account.isReserve)
      ? undefined
      : offered.find(account => CASH_ACCOUNT_TYPES.includes(account.type))
    for (const account of offered) {
      await deps.accounts.save(
        createAccount({
          id: deps.ids.next(),
          tenantId,
          entityId,
          institutionId: institution.id,
          name: account.name,
          type: account.type,
          origin: 'CONNECTED',
          isReserve: account === reserve,
          balance: Money.of(account.balanceCents, account.currency),
          connectionId: connection.id,
          externalId: account.externalId,
          numberSuffix: account.numberSuffix ?? null,
        }),
      )
    }
    return connection
  }

  async function uses(tenantId: string, entity: FinancialEntity) {
    const settings = await deps.settings.get(tenantId, entity.id)
    // Unsaved settings enable every rail, so the route decides who uses it.
    return (
      routesThrough(entity.kind, RAIL) && settings.enabledRails.includes(RAIL)
    )
  }

  // Each entity that pays through the rail gets its account once; one without
  // rail credentials has nothing to read yet.
  async function connectionOf(
    tenantId: string,
    entityId: string,
  ): Promise<Connection | null> {
    const existing = await deps.connections.findByItemId(
      tenantId,
      RAIL_ACCOUNT_PROVIDER,
      railAccountItemId(entityId),
    )
    if (existing) {
      return existing
    }
    return connect(tenantId, entityId).catch((error: unknown) => {
      if (error instanceof ProviderNotConfiguredError) {
        return null
      }
      throw error
    })
  }

  async function syncEntity(tenantId: string, entityId: string) {
    const connection = await connectionOf(tenantId, entityId)
    if (!connection) {
      return { accounts: 0, transactions: 0 }
    }
    const { transactions } = await syncConnection(tenantId, connection.id)
    return { accounts: 1, transactions }
  }

  async function sync(tenantId: string) {
    const failures: Array<{ entityId: string; reason: string }> = []
    let accounts = 0
    let transactions = 0
    for (const entity of await deps.entities.list(tenantId)) {
      if (!(await uses(tenantId, entity))) {
        continue
      }
      try {
        const synced = await syncEntity(tenantId, entity.id)
        accounts += synced.accounts
        transactions += synced.transactions
      } catch (error) {
        failures.push({ entityId: entity.id, reason: String(error) })
      }
    }
    return { accounts, transactions, failures }
  }

  return { sync }
}
