import {
  type Account,
  addDays,
  createAccount,
  createTransaction,
  Money,
} from '@cashdeck/domain'
import { type z } from 'zod'
import { money } from '@/dtos/common'
import {
  type connectItemSchema,
  type ConnectionView,
  type ItemLookupView,
} from '@/dtos/open-finance'
import { NotFoundError } from '@/errors/errors'
import { type ProviderAccount, type ProviderItem } from '@/ports/providers'
import { type Connection } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { makeSettleFromStatement } from '@/use-cases/settle-from-statement'
import {
  required,
  requireEntity,
  requireEntityById,
  today,
} from '@/use-cases/shared'

export const OPEN_FINANCE_PROVIDER = 'pluggy'
const FIRST_SYNC_DAYS = 30

type OpenFinanceDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'institutions'
  | 'transactions'
  | 'connections'
  | 'openFinance'
  | 'clock'
  | 'ids'
  | 'bills'
  | 'audit'
>

// The provider already reports a card balance as negative, since it is owed.
const balanceOf = (account: ProviderAccount) =>
  Money.of(account.balanceCents, account.currency)

// An adapter reports an unknown item as NotFoundError or as an HTTP 404.
const isMissing = (error: unknown) =>
  error instanceof NotFoundError ||
  (error as { status?: unknown } | null)?.status === 404

async function findItem(
  deps: Pick<Deps, 'openFinance'>,
  itemId: string,
): Promise<ProviderItem | null> {
  try {
    return await deps.openFinance.getItem(itemId)
  } catch (error) {
    if (isMissing(error)) {
      return null
    }
    throw error
  }
}

const connectionOf = (itemId: string) => ({
  provider: OPEN_FINANCE_PROVIDER,
  itemId,
})

export function makeOpenFinance(deps: OpenFinanceDeps) {
  const settleFromStatement = makeSettleFromStatement(deps)

  async function lookup(
    tenantId: string,
    itemId: string,
  ): Promise<ItemLookupView> {
    const existing = await deps.connections.findByItemId(
      tenantId,
      OPEN_FINANCE_PROVIDER,
      itemId,
    )
    if (existing) {
      const owner = await requireEntityById(
        deps.entities,
        tenantId,
        existing.entityId,
      )
      return { status: 'ALREADY_CONNECTED', owner: owner.kind }
    }
    const item = await findItem(deps, itemId)
    if (!item) {
      return { status: 'NOT_FOUND' }
    }
    const accounts = await deps.openFinance.listAccounts(connectionOf(itemId))
    return {
      status: 'FOUND',
      institution: item.institutionName,
      consentUntil: null,
      accounts: accounts.map(account => ({
        id: account.externalId,
        name: account.name,
        balance: money(balanceOf(account)),
      })),
    }
  }

  async function connect(
    tenantId: string,
    input: z.infer<typeof connectItemSchema>,
  ): Promise<{ connectionId: string; imported: number }> {
    const found = await lookup(tenantId, input.itemId)
    if (found.status !== 'FOUND') {
      throw new NotFoundError('Item')
    }
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const item = await deps.openFinance.getItem(input.itemId)
    const institution = await deps.institutions.ensure({
      id: deps.ids.next(),
      tenantId,
      name: item.institutionName,
      manual: false,
    })
    const connection: Connection = {
      id: deps.ids.next(),
      tenantId,
      entityId: entity.id,
      institutionId: institution.id,
      provider: OPEN_FINANCE_PROVIDER,
      itemId: input.itemId,
      status: item.status,
      lastSyncAt: null,
    }
    await deps.connections.save(connection)
    const offered = await deps.openFinance.listAccounts(
      connectionOf(input.itemId),
    )
    const chosen = offered.filter(account =>
      input.accountIds.includes(account.externalId),
    )
    for (const account of chosen) {
      await deps.accounts.save(
        createAccount({
          id: deps.ids.next(),
          tenantId,
          entityId: entity.id,
          institutionId: institution.id,
          name: account.name,
          type: account.type,
          origin: 'CONNECTED',
          balance: balanceOf(account),
          connectionId: connection.id,
          externalId: account.externalId,
        }),
      )
    }
    return { connectionId: connection.id, imported: chosen.length }
  }

  async function list(tenantId: string): Promise<ConnectionView[]> {
    const connections = await deps.connections.list(tenantId)
    const accounts = await deps.accounts.list(tenantId)
    const views: ConnectionView[] = []
    for (const connection of connections) {
      const entity = await requireEntityById(
        deps.entities,
        tenantId,
        connection.entityId,
      )
      const institution = await deps.institutions.findById(
        tenantId,
        connection.institutionId,
      )
      views.push({
        id: connection.id,
        itemId: connection.itemId,
        institution: institution?.name ?? '',
        entityKind: entity.kind,
        status: connection.status,
        lastSyncAt: connection.lastSyncAt?.toISOString() ?? null,
        accountCount: accounts.filter(a => a.connectionId === connection.id)
          .length,
      })
    }
    return views
  }

  async function syncAccount(
    tenantId: string,
    connection: Connection,
    account: Account,
    remote: ProviderAccount | undefined,
    range: { from: string; to: string },
  ): Promise<number> {
    if (!remote) {
      return 0
    }
    await deps.accounts.save({ ...account, balance: balanceOf(remote) })
    const fetched = await deps.openFinance.listTransactions(
      connectionOf(connection.itemId),
      remote.externalId,
      range,
    )
    return deps.transactions.saveNew(
      fetched.map(tx =>
        createTransaction({
          id: deps.ids.next(),
          tenantId,
          accountId: account.id,
          amount: Money.of(tx.amountCents, tx.currency),
          bookedOn: tx.bookedOn,
          description: tx.description,
          externalId: tx.externalId,
        }),
      ),
    )
  }

  async function sync(tenantId: string, connectionId: string) {
    const connection = required(
      await deps.connections.findById(tenantId, connectionId),
      'Connection',
    )
    const now = deps.clock.now()
    const day = today(now)
    const from = connection.lastSyncAt
      ? addDays(today(connection.lastSyncAt), -1)
      : addDays(day, -FIRST_SYNC_DAYS)
    const accounts = (await deps.accounts.list(tenantId)).filter(
      account => account.connectionId === connection.id,
    )
    const remote = await deps.openFinance.listAccounts(
      connectionOf(connection.itemId),
    )
    let transactions = 0
    for (const account of accounts) {
      transactions += await syncAccount(
        tenantId,
        connection,
        account,
        remote.find(candidate => candidate.externalId === account.externalId),
        { from, to: day },
      )
    }
    await deps.connections.save({
      ...connection,
      lastSyncAt: now,
      status: 'UPDATED',
    })
    return {
      accounts: accounts.length,
      transactions,
      settledBills: await settleFromStatement(tenantId, connection.entityId),
      syncedAt: now.toISOString(),
    }
  }

  async function syncAll(tenantId: string) {
    const connections = await deps.connections.list(tenantId)
    const failures: Array<{ connectionId: string; reason: string }> = []
    let transactions = 0
    for (const connection of connections) {
      try {
        transactions += (await sync(tenantId, connection.id)).transactions
      } catch (error) {
        failures.push({ connectionId: connection.id, reason: String(error) })
      }
    }
    return { connections: connections.length, transactions, failures }
  }

  async function remove(tenantId: string, connectionId: string) {
    const connection = required(
      await deps.connections.findById(tenantId, connectionId),
      'Connection',
    )
    const accounts = await deps.accounts.list(tenantId)
    for (const account of accounts.filter(
      a => a.connectionId === connection.id,
    )) {
      await deps.accounts.save({
        ...account,
        connectionId: null,
        origin: 'MANUAL',
      })
    }
    await deps.connections.delete(tenantId, connection.id)
    return { id: connection.id }
  }

  return { lookup, connect, list, sync, syncAll, remove }
}
