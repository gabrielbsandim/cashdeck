import {
  type Account,
  addDays,
  createAccount,
  createTransaction,
  type CreditLine,
  Money,
} from '@cashdeck/domain'
import { type z } from 'zod'
import { money } from '@/dtos/common'
import {
  type connectItemSchema,
  type ConnectionView,
  type ItemLookupView,
  type SyncOptions,
} from '@/dtos/open-finance'
import { NotFoundError } from '@/errors/errors'
import {
  type ProviderAccount,
  type ProviderConnector,
  type ProviderItem,
  type ProviderTransaction,
} from '@/ports/providers'
import { type Connection, type Institution } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { isAggregator, matchConnector } from '@/use-cases/institution-match'
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
  | 'cardBills'
  | 'connections'
  | 'openFinance'
  | 'clock'
  | 'ids'
  | 'bills'
  | 'alertStore'
  | 'audit'
  | 'documents'
>

// The provider already reports a card balance as negative, since it is owed.
const balanceOf = (account: ProviderAccount) =>
  Money.of(account.balanceCents, account.currency)

function creditOf(account: ProviderAccount): CreditLine | null {
  const credit = account.credit
  if (account.type !== 'CREDIT_CARD' || !credit) {
    return null
  }
  return {
    limit: Money.of(credit.limitCents, account.currency),
    available: Money.of(credit.availableCents, account.currency),
    closesOn: credit.closesOn,
    dueOn: credit.dueOn,
    brand: credit.brand,
  }
}

const detailsOf = (account: ProviderAccount) => ({
  numberSuffix: account.numberSuffix ?? null,
  credit: creditOf(account),
})

const brandingOf = (connector: ProviderConnector | null | undefined) => ({
  connectorId: connector?.id ?? null,
  imageUrl: connector?.imageUrl ?? null,
  primaryColor: connector?.primaryColor ?? null,
})

// How far back a sync may reach when asked to fetch history again.
export const MAX_SYNC_DAYS = 365

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

  // Logos are a nicety: a provider that cannot list connectors leaves the
  // accounts under the connection's own institution.
  async function connectors(): Promise<ProviderConnector[]> {
    try {
      return await deps.openFinance.listConnectors()
    } catch {
      return []
    }
  }

  async function institutionResolver(
    tenantId: string,
    institution: Institution,
  ): Promise<(accountName: string) => Promise<Institution | null>> {
    if (!isAggregator(institution.name)) {
      return async () => null
    }
    const known = await connectors()
    return async accountName => {
      const connector = matchConnector(accountName, known)
      if (!connector) {
        return null
      }
      return deps.institutions.ensure({
        id: deps.ids.next(),
        tenantId,
        name: connector.name,
        manual: false,
        ...brandingOf(connector),
      })
    }
  }

  const toTransaction = (
    tenantId: string,
    account: Account,
    tx: ProviderTransaction,
  ) =>
    createTransaction({
      id: deps.ids.next(),
      tenantId,
      accountId: account.id,
      amount: Money.of(tx.amountCents, tx.currency),
      bookedOn: tx.bookedOn,
      description: tx.description,
      externalId: tx.externalId,
      merchant: tx.merchant ?? null,
      installment: tx.installment ?? null,
    })

  // Bills are history for the cards screen; a failure there never fails the
  // sync of balances and transactions.
  async function syncBills(
    connection: Connection,
    account: Account,
  ): Promise<void> {
    if (account.type !== 'CREDIT_CARD' || !account.externalId) {
      return
    }
    const bills = await deps.openFinance
      .listBills(connectionOf(connection.itemId), account.externalId)
      .catch(() => [])
    await deps.cardBills.saveAll(
      bills.map(bill => ({
        id: deps.ids.next(),
        tenantId: account.tenantId,
        accountId: account.id,
        externalId: bill.externalId,
        closesOn: bill.closesOn,
        dueOn: bill.dueOn,
        total: Money.of(bill.totalCents, bill.currency),
        minimum:
          bill.minimumCents === null
            ? null
            : Money.of(bill.minimumCents, bill.currency),
      })),
    )
  }

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
      ...brandingOf(item.connector),
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
    const resolve = await institutionResolver(tenantId, institution)
    for (const account of chosen) {
      const owner = await resolve(account.name)
      await deps.accounts.save(
        createAccount({
          id: deps.ids.next(),
          tenantId,
          entityId: entity.id,
          institutionId: owner?.id ?? institution.id,
          name: account.name,
          type: account.type,
          origin: 'CONNECTED',
          balance: balanceOf(account),
          connectionId: connection.id,
          externalId: account.externalId,
          ...detailsOf(account),
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

  type AccountSync = {
    connection: Connection
    resolve: (accountName: string) => Promise<Institution | null>
    range: { from: string; to: string }
  }

  async function syncAccount(
    tenantId: string,
    account: Account,
    remote: ProviderAccount | undefined,
    context: AccountSync,
  ): Promise<number> {
    if (!remote) {
      return 0
    }
    const owner = await context.resolve(remote.name)
    const synced: Account = {
      ...account,
      balance: balanceOf(remote),
      institutionId: owner?.id ?? account.institutionId,
      ...detailsOf(remote),
    }
    await deps.accounts.save(synced)
    await syncBills(context.connection, synced)
    const fetched = await deps.openFinance.listTransactions(
      connectionOf(context.connection.itemId),
      remote.externalId,
      context.range,
    )
    return deps.transactions.saveNew(
      fetched.map(tx => toTransaction(tenantId, synced, tx)),
    )
  }

  function syncStart(connection: Connection, day: string, days?: number) {
    if (days) {
      return addDays(day, -Math.min(days, MAX_SYNC_DAYS))
    }
    if (connection.lastSyncAt) {
      return addDays(today(connection.lastSyncAt), -1)
    }
    return addDays(day, -FIRST_SYNC_DAYS)
  }

  async function sync(
    tenantId: string,
    connectionId: string,
    options: SyncOptions = {},
  ) {
    const connection = required(
      await deps.connections.findById(tenantId, connectionId),
      'Connection',
    )
    const now = deps.clock.now()
    const day = today(now)
    const accounts = (await deps.accounts.list(tenantId)).filter(
      account => account.connectionId === connection.id,
    )
    const remote = await deps.openFinance.listAccounts(
      connectionOf(connection.itemId),
    )
    const institution = await deps.institutions.findById(
      tenantId,
      connection.institutionId,
    )
    const context: AccountSync = {
      connection,
      resolve: institution
        ? await institutionResolver(tenantId, institution)
        : async () => null,
      range: { from: syncStart(connection, day, options.days), to: day },
    }
    let transactions = 0
    for (const account of accounts) {
      transactions += await syncAccount(
        tenantId,
        account,
        remote.find(candidate => candidate.externalId === account.externalId),
        context,
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
