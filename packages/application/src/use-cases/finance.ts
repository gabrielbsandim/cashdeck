import {
  type Account,
  addDays,
  createAccount,
  createFinancialEntity,
  createTransaction,
  type CreditLine,
  creditUsedPercent,
  type EntityKind,
  type FinancialEntity,
  Money,
  type Transaction,
  transactionKind,
  ValidationError,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type AccountView,
  type createAccountSchema,
  type listTransactionsQuerySchema,
  type recordTransferSchema,
  type TransactionView,
  type TransferView,
  type updateAccountSchema,
  type updateEntitySchema,
} from '@/dtos/finance'
import { type Institution, type InternalTransfer } from '@/ports/records'
import { type Page } from '@/ports/repositories'
import { type Deps } from '@/use-cases/deps'
import {
  monthInstants,
  monthOf,
  required,
  requireEntity,
  today,
} from '@/use-cases/shared'
import { type z } from 'zod'

type EntityIndex = Map<string, FinancialEntity>

async function entityIndex(
  deps: Pick<Deps, 'entities'>,
  tenantId: string,
): Promise<EntityIndex> {
  const all = await deps.entities.list(tenantId)
  return new Map(all.map(entity => [entity.id, entity]))
}

function kindOf(index: EntityIndex, entityId: string): EntityKind {
  return required(index.get(entityId) ?? null, 'Entity').kind
}

function entityView(entity: FinancialEntity) {
  return {
    id: entity.id,
    kind: entity.kind,
    name: entity.name,
    taxId: entity.taxId.value,
    taxRegime: entity.taxRegime,
  }
}

export function makeListEntities(deps: Pick<Deps, 'entities'>) {
  return async function listEntities(tenantId: string) {
    const all = await deps.entities.list(tenantId)
    return all.sort((a, b) => a.kind.localeCompare(b.kind)).map(entityView)
  }
}

// The seed ships placeholder tax ids; the real ones are set here before any
// issuer, rail or DDA call uses them.
export function makeUpdateEntity(
  deps: Pick<Deps, 'entities' | 'audit' | 'ids' | 'clock'>,
) {
  return async function updateEntity(
    tenantId: string,
    id: string,
    input: z.infer<typeof updateEntitySchema>,
  ) {
    const current = required(
      await deps.entities.findById(tenantId, id),
      'Entity',
    )
    const updated = createFinancialEntity({
      id: current.id,
      tenantId,
      kind: current.kind,
      name: input.name ?? current.name,
      taxId: input.taxId ?? current.taxId.value,
      taxRegime:
        input.taxRegime === undefined ? current.taxRegime : input.taxRegime,
    })
    await deps.entities.save(updated)
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'USER',
      action: 'entity.update',
      subjectId: id,
      rail: null,
      result: 'UPDATED',
      details: { fields: Object.keys(input) },
      at: deps.clock.now(),
    })
    return entityView(updated)
  }
}

function creditView(credit: CreditLine | null): AccountView['credit'] {
  if (!credit) {
    return null
  }
  return {
    limit: money(credit.limit),
    available: money(credit.available),
    usedPercent: creditUsedPercent(credit),
    closesOn: credit.closesOn,
    dueOn: credit.dueOn,
    brand: credit.brand,
  }
}

function logoView(institution: Institution | null): AccountView['logo'] {
  if (!institution?.imageUrl) {
    return null
  }
  return {
    imageUrl: institution.imageUrl,
    color: institution.primaryColor ?? null,
  }
}

export function makeAccountViews(
  deps: Pick<Deps, 'entities' | 'institutions' | 'connections'>,
) {
  return async function accountViews(
    tenantId: string,
    accounts: readonly Account[],
  ): Promise<AccountView[]> {
    const index = await entityIndex(deps, tenantId)
    const connections = await deps.connections.list(tenantId)
    const views: AccountView[] = []
    for (const account of accounts) {
      const institution = await deps.institutions.findById(
        tenantId,
        account.institutionId,
      )
      const connection = connections.find(
        candidate => candidate.id === account.connectionId,
      )
      views.push({
        id: account.id,
        entityKind: kindOf(index, account.entityId),
        institution: institution?.name ?? '',
        name: account.name,
        type: account.type,
        origin: account.origin,
        isReserve: account.isReserve,
        balance: money(account.balance),
        cdiPercent: account.cdiPercent,
        connectionId: account.connectionId,
        numberSuffix: account.numberSuffix,
        logo: logoView(institution),
        credit: creditView(account.credit),
        sync: connection
          ? {
              status: connection.status,
              lastSyncAt: connection.lastSyncAt?.toISOString() ?? null,
            }
          : null,
      })
    }
    return views
  }
}

async function accountsOf(
  deps: Pick<Deps, 'entities' | 'accounts'>,
  tenantId: string,
  kind: EntityKind | undefined,
): Promise<Account[]> {
  if (!kind) {
    return deps.accounts.list(tenantId)
  }
  const entity = await requireEntity(deps.entities, tenantId, kind)
  return deps.accounts.listByEntity(tenantId, entity.id)
}

export function makeListAccounts(
  deps: Pick<Deps, 'entities' | 'accounts' | 'institutions' | 'connections'>,
) {
  const views = makeAccountViews(deps)
  return async function listAccounts(
    tenantId: string,
    kind?: EntityKind,
  ): Promise<AccountView[]> {
    const accounts = await accountsOf(deps, tenantId, kind)
    return views(
      tenantId,
      accounts.sort((a, b) => a.name.localeCompare(b.name)),
    )
  }
}

// One reserve per entity: picking a new one releases the previous.
async function releaseReserve(
  deps: Pick<Deps, 'accounts'>,
  account: Account,
): Promise<void> {
  const siblings = await deps.accounts.listByEntity(
    account.tenantId,
    account.entityId,
  )
  for (const sibling of siblings) {
    if (sibling.id === account.id || !sibling.isReserve) {
      continue
    }
    await deps.accounts.save({ ...sibling, isReserve: false })
  }
}

export function makeCreateManualAccount(
  deps: Pick<
    Deps,
    'entities' | 'accounts' | 'institutions' | 'connections' | 'ids'
  >,
) {
  const views = makeAccountViews(deps)
  return async function createManualAccount(
    tenantId: string,
    input: z.infer<typeof createAccountSchema>,
  ): Promise<AccountView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const institution = await deps.institutions.ensure({
      id: deps.ids.next(),
      tenantId,
      name: input.institution,
      manual: true,
    })
    const account = createAccount({
      id: deps.ids.next(),
      tenantId,
      entityId: entity.id,
      institutionId: institution.id,
      name: input.name,
      type: input.type,
      origin: 'MANUAL',
      isReserve: input.isReserve,
      balance: Money.of(input.balanceCents, input.currency),
    })
    await deps.accounts.save(account)
    if (account.isReserve) {
      await releaseReserve(deps, account)
    }
    return (await views(tenantId, [account]))[0] as AccountView
  }
}

export function makeUpdateAccount(
  deps: Pick<Deps, 'entities' | 'accounts' | 'institutions' | 'connections'>,
) {
  const views = makeAccountViews(deps)
  return async function updateAccount(
    tenantId: string,
    id: string,
    input: z.infer<typeof updateAccountSchema>,
  ): Promise<AccountView> {
    const account = required(
      await deps.accounts.findById(tenantId, id),
      'Account',
    )
    if (input.balanceCents !== undefined && account.origin !== 'MANUAL') {
      throw new ValidationError('Only a manual account balance can be set.')
    }
    const balance =
      input.balanceCents === undefined
        ? account.balance
        : Money.of(input.balanceCents, account.balance.currency)
    const updated = createAccount({
      ...account,
      name: input.name ?? account.name,
      isReserve: input.isReserve ?? account.isReserve,
      cdiPercent:
        input.cdiPercent === undefined ? account.cdiPercent : input.cdiPercent,
      balance,
    })
    await deps.accounts.save(updated)
    if (updated.isReserve) {
      await releaseReserve(deps, updated)
    }
    return (await views(tenantId, [updated]))[0] as AccountView
  }
}

export function toTransactionView(
  transaction: Transaction,
  entityKind: EntityKind,
): TransactionView {
  return {
    id: transaction.id,
    accountId: transaction.accountId,
    entityKind,
    amount: money(transaction.amount),
    bookedOn: transaction.bookedOn,
    description: transaction.description,
    categoryId: transaction.categoryId,
    kind: transactionKind(transaction),
    transferId: transaction.transferGroupId,
    invoiceId: transaction.invoiceId,
    note: transaction.note,
    categorizedBy: transaction.categorizedBy,
    categoryConfidence: transaction.categoryConfidence,
    merchant: transaction.merchant,
    installment: transaction.installment,
  }
}

export function makeListTransactions(
  deps: Pick<Deps, 'entities' | 'accounts' | 'transactions'>,
) {
  return async function listTransactions(
    tenantId: string,
    query: z.infer<typeof listTransactionsQuerySchema>,
  ): Promise<Page<TransactionView>> {
    const accounts = await accountsOf(deps, tenantId, query.entity)
    const owners = new Map(accounts.map(a => [a.id, a.entityId]))
    const index = await entityIndex(deps, tenantId)
    const accountIds = query.accountId
      ? accounts.filter(a => a.id === query.accountId).map(a => a.id)
      : accounts.map(a => a.id)
    const page = await deps.transactions.list(
      tenantId,
      {
        accountIds,
        from: query.from,
        to: query.to,
        categoryId: query.categoryId,
        uncategorized: query.uncategorized,
        search: query.search,
      },
      { cursor: query.cursor, limit: query.limit },
    )
    return {
      items: page.items.map(tx =>
        toTransactionView(
          tx,
          kindOf(index, owners.get(tx.accountId) as string),
        ),
      ),
      nextCursor: page.nextCursor,
    }
  }
}

export function makeTransferViews(deps: Pick<Deps, 'entities' | 'accounts'>) {
  return async function transferView(
    tenantId: string,
    transfer: InternalTransfer,
  ): Promise<TransferView> {
    const index = await entityIndex(deps, tenantId)
    const party = async (accountId: string) => {
      const account = required(
        await deps.accounts.findById(tenantId, accountId),
        'Account',
      )
      const entity = required(index.get(account.entityId) ?? null, 'Entity')
      return {
        owner: entity.kind,
        holder: entity.name,
        account: account.name,
        accountId: account.id,
      }
    }
    return {
      id: transfer.id,
      kind: transfer.kind,
      amount: money(transfer.amount),
      at: transfer.at.toISOString(),
      rail: transfer.rail,
      from: await party(transfer.fromAccountId),
      to: await party(transfer.toAccountId),
      document: transfer.document,
      neutral: transfer.kind === 'PROFIT_DISTRIBUTION',
    }
  }
}

export function makeListTransfers(
  deps: Pick<Deps, 'entities' | 'accounts' | 'transfers' | 'clock'>,
) {
  const view = makeTransferViews(deps)
  return async function listTransfers(
    tenantId: string,
    month: string = monthOf(today(deps.clock.now())),
  ): Promise<TransferView[]> {
    const found = await deps.transfers.list(tenantId, monthInstants(month))
    const views: TransferView[] = []
    for (const transfer of found) {
      views.push(await view(tenantId, transfer))
    }
    return views
  }
}

export function makeGetTransfer(
  deps: Pick<Deps, 'entities' | 'accounts' | 'transfers'>,
) {
  const view = makeTransferViews(deps)
  return async function getTransfer(
    tenantId: string,
    id: string,
  ): Promise<TransferView> {
    const transfer = required(
      await deps.transfers.findById(tenantId, id),
      'Transfer',
    )
    return view(tenantId, transfer)
  }
}

const LINK_WINDOW_DAYS = 2

async function linkTransaction(
  deps: Pick<Deps, 'transactions'>,
  tenantId: string,
  accountId: string,
  cents: number,
  day: string,
  transferId: string,
): Promise<void> {
  const candidates = await deps.transactions.all(tenantId, {
    accountIds: [accountId],
    from: addDays(day, -LINK_WINDOW_DAYS),
    to: addDays(day, LINK_WINDOW_DAYS),
  })
  const match = candidates.find(
    tx => tx.transferGroupId === null && tx.amount.cents === cents,
  )
  if (!match) {
    return
  }
  await deps.transactions.save(
    createTransaction({ ...match, transferGroupId: transferId }),
  )
}

export function makeRecordTransfer(
  deps: Pick<
    Deps,
    'entities' | 'accounts' | 'transfers' | 'transactions' | 'clock' | 'ids'
  >,
) {
  const view = makeTransferViews(deps)
  return async function recordTransfer(
    tenantId: string,
    input: z.infer<typeof recordTransferSchema>,
  ): Promise<TransferView> {
    const [from, to] = await Promise.all([
      deps.accounts.findById(tenantId, input.fromAccountId),
      deps.accounts.findById(tenantId, input.toAccountId),
    ])
    const source = required(from, 'Account')
    const target = required(to, 'Account')
    if (source.entityId === target.entityId) {
      throw new ValidationError('A transfer moves money between entities.')
    }
    const transfer: InternalTransfer = {
      id: deps.ids.next(),
      tenantId,
      kind: input.kind,
      amount: Money.of(input.amountCents, source.balance.currency),
      at: input.at ? new Date(input.at) : deps.clock.now(),
      rail: input.rail,
      fromAccountId: source.id,
      toAccountId: target.id,
      document: input.document ?? null,
    }
    await deps.transfers.save(transfer)
    const day = today(transfer.at)
    await linkTransaction(
      deps,
      tenantId,
      source.id,
      -input.amountCents,
      day,
      transfer.id,
    )
    await linkTransaction(
      deps,
      tenantId,
      target.id,
      input.amountCents,
      day,
      transfer.id,
    )
    return view(tenantId, transfer)
  }
}
