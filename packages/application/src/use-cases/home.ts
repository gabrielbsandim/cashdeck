import {
  type Account,
  addDays,
  averageDailyFlow,
  type Bill,
  CASH_ACCOUNT_TYPES,
  coverDays,
  dasDueDate,
  daysBetween,
  estimateDas,
  type FinancialEntity,
  isSettled,
  type LocalDate,
  Money,
  projectBalances,
  proLaboreInss,
  type Transaction,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type CompanySummary,
  type ConsolidatedSummary,
  type PersonalSummary,
} from '@/dtos/home'
import { type Deps } from '@/use-cases/deps'
import { payrollWindow } from '@/use-cases/payroll'
import { isRailAccountItem } from '@/use-cases/rail-accounts'
import { issQuote } from '@/use-cases/revenue'
import {
  addMonths,
  brlOf,
  firstDay,
  lastDay,
  monthInstants,
  monthOf,
  requireEntity,
  today,
} from '@/use-cases/shared'

const FORECAST_DAYS = 30
const COVER_CAP_DAYS = 90
const UNBILLED_DAYS = 60
const BILL_PAGE = { limit: 100 }

const isCash = (account: Account) =>
  CASH_ACCOUNT_TYPES.includes(account.type) &&
  account.balance.currency === 'BRL'

const sum = (values: readonly Money[]) =>
  values.reduce((total, value) => total.add(value), Money.zero())

type Scope = { entity: FinancialEntity; accounts: Account[] }

async function scopeOf(
  deps: Pick<Deps, 'entities' | 'accounts'>,
  tenantId: string,
  kind: FinancialEntity['kind'],
): Promise<Scope> {
  const entity = await requireEntity(deps.entities, tenantId, kind)
  return {
    entity,
    accounts: await deps.accounts.listByEntity(tenantId, entity.id),
  }
}

async function syncOf(
  deps: Pick<Deps, 'connections'>,
  tenantId: string,
  scope: Scope,
) {
  const connected = scope.accounts.filter(
    account => account.connectionId !== null,
  )
  const connections = await deps.connections.list(tenantId)
  const times = connections
    .filter(connection => connection.entityId === scope.entity.id)
    // The rail is read live, so its time would hide a stale bank feed.
    .filter(connection => !isRailAccountItem(connection.itemId))
    .map(connection => connection.lastSyncAt?.getTime() ?? 0)
    .filter(time => time > 0)
  return {
    accountCount: connected.length,
    syncedAt: times.length ? new Date(Math.max(...times)).toISOString() : null,
  }
}

async function openBills(
  deps: Pick<Deps, 'bills'>,
  tenantId: string,
  entityId: string,
): Promise<Bill[]> {
  const page = await deps.bills.list(tenantId, { entityId }, BILL_PAGE)
  return page.items.filter(bill => !isSettled(bill))
}

function cashTransactions(
  deps: Pick<Deps, 'transactions'>,
  tenantId: string,
  accounts: readonly Account[],
  range: { from: LocalDate; to: LocalDate },
): Promise<Transaction[]> {
  return deps.transactions.all(tenantId, {
    accountIds: accounts.map(account => account.id),
    ...range,
  })
}

async function assistedAlerts(
  deps: Pick<Deps, 'bills' | 'payments'>,
  tenantId: string,
  entityId: string,
) {
  const page = await deps.bills.list(
    tenantId,
    { entityId, status: 'ASSISTED' },
    BILL_PAGE,
  )
  return Promise.all(
    page.items.map(async (bill): Promise<PersonalSummary['alerts'][number]> => {
      const attempts = await deps.payments.listAttempts(tenantId, bill.id)
      const failed = attempts
        .filter(attempt => attempt.outcome === 'FAILED')
        .at(-1)
      return {
        type: 'ASSISTED_PAYMENT',
        at: (attempts.at(-1)?.at ?? bill.createdAt).toISOString(),
        billId: bill.id,
        payee: bill.payee ?? '',
        reason: failed?.reason ?? 'NOT_CONFIGURED',
      }
    }),
  )
}

export function makePersonalSummary(
  deps: Pick<
    Deps,
    | 'entities'
    | 'accounts'
    | 'institutions'
    | 'connections'
    | 'transactions'
    | 'bills'
    | 'payments'
    | 'budgets'
    | 'clock'
  >,
) {
  return async function personalSummary(
    tenantId: string,
  ): Promise<PersonalSummary> {
    const now = deps.clock.now()
    const day = today(now)
    const month = monthOf(day)
    const scope = await scopeOf(deps, tenantId, 'PF')
    const cash = scope.accounts.filter(isCash)
    const spending = cash.filter(account => !account.isReserve)
    const reserveAccount = cash.find(account => account.isReserve) ?? null
    const balance = sum(spending.map(account => account.balance))
    // Every read below depends only on the scope, so they share one round trip.
    const [open, recent, budgets, sync, assisted] = await Promise.all([
      openBills(deps, tenantId, scope.entity.id),
      cashTransactions(deps, tenantId, spending, {
        from: addDays(day, -FORECAST_DAYS),
        to: day,
      }),
      budgetsOf(deps, tenantId, scope, month),
      syncOf(deps, tenantId, scope),
      assistedAlerts(deps, tenantId, scope.entity.id),
    ])
    const bills = open.map(bill => ({
      day: daysBetween(day, bill.dueDate),
      amount: bill.amount,
    }))
    const flow = recent
      .filter(tx => tx.transferGroupId === null)
      .map(tx => tx.amount)
    const start = balance.add(reserveAccount?.balance ?? Money.zero())
    const forecast = projectBalances({
      start,
      dailyFlow: averageDailyFlow(flow, FORECAST_DAYS),
      events: bills
        .filter(bill => bill.day >= 0)
        .map(bill => ({ day: bill.day, amount: bill.amount.negate() })),
      days: FORECAST_DAYS,
    })
    return {
      balance: money(balance),
      sync,
      reserve:
        reserveAccount &&
        (await reserveOf(deps, tenantId, reserveAccount, month, bills)),
      forecast: {
        from: day,
        balances: forecast.map(money),
        floor: money(Money.zero()),
      },
      budgets,
      alerts: [
        ...assisted,
        ...budgets
          .filter(budget => budget.spent.cents > budget.limit.cents)
          .map(budget => ({
            type: 'BUDGET_EXCEEDED' as const,
            at: now.toISOString(),
            budget,
          })),
      ],
    }
  }
}

async function reserveOf(
  deps: Pick<Deps, 'institutions' | 'transactions'>,
  tenantId: string,
  account: Account,
  month: string,
  bills: Array<{ day: number; amount: Money }>,
) {
  const [institution, credits] = await Promise.all([
    deps.institutions.findById(tenantId, account.institutionId),
    deps.transactions.all(tenantId, {
      accountIds: [account.id],
      from: firstDay(month),
    }),
  ])
  const yields = credits
    .filter(tx => tx.amount.isPositive() && tx.transferGroupId === null)
    .map(tx => tx.amount)
  return {
    accountId: account.id,
    institution: institution?.name ?? '',
    product: account.name,
    balance: money(account.balance),
    monthYield: money(sum(yields)),
    coverDays: coverDays(account.balance, bills, COVER_CAP_DAYS),
    cdiPercent: account.cdiPercent,
  }
}

async function budgetsOf(
  deps: Pick<Deps, 'budgets' | 'transactions'>,
  tenantId: string,
  scope: Scope,
  month: string,
) {
  const [limits, spent] = await Promise.all([
    deps.budgets.list(tenantId, scope.entity.id, month),
    cashTransactions(deps, tenantId, scope.accounts, {
      from: firstDay(month),
      to: lastDay(month),
    }),
  ])
  return limits.map(limit => ({
    category: limit.categoryName.toLowerCase(),
    spent: money(
      sum(
        spent
          .filter(
            tx => tx.categoryId === limit.categoryId && tx.amount.isNegative(),
          )
          .map(tx => tx.amount.negate()),
      ),
    ),
    limit: money(limit.limit),
  }))
}

export function makeCompanySummary(
  deps: Pick<
    Deps,
    | 'entities'
    | 'accounts'
    | 'connections'
    | 'transactions'
    | 'invoices'
    | 'documents'
    | 'clock'
  >,
) {
  return async function companySummary(
    tenantId: string,
  ): Promise<CompanySummary> {
    const day = today(deps.clock.now())
    const month = monthOf(day)
    const scope = await scopeOf(deps, tenantId, 'PJ')
    const cash = scope.accounts.filter(isCash)
    const [issued, quote, sync, inss, drafts, unbilled] = await Promise.all([
      deps.invoices.all(tenantId, {
        entityId: scope.entity.id,
        status: 'ISSUED',
        competenceFrom: month,
        competenceTo: month,
      }),
      issQuote(deps, tenantId, scope.entity.id, month),
      syncOf(deps, tenantId, scope),
      inssOf(deps, tenantId, day),
      draftsOf(deps, tenantId, scope.entity.id),
      unbilledOf(deps, tenantId, cash, day),
    ])
    const domestic = sum(issued.filter(i => !i.isExport).map(brlOf))
    const exports = sum(issued.filter(i => i.isExport).map(brlOf))
    const { annex, domesticRbt12, exportRbt12 } = quote
    return {
      cash: money(sum(cash.map(account => account.balance))),
      sync,
      billed: money(domestic.add(exports)),
      invoiceCount: issued.length,
      dasEstimate: money(
        estimateDas({ annex, domesticRbt12, exportRbt12, domestic, exports }),
      ),
      dasDue: dasDueDate(month),
      inss,
      annex,
      drafts,
      unbilled,
    }
  }
}

// The pro-labore guide still to pay: last month's until its due date passes.
// A month without payroll entered repeats the latest pro-labore before it.
async function inssOf(
  deps: Pick<Deps, 'documents'>,
  tenantId: string,
  day: LocalDate,
): Promise<CompanySummary['inss']> {
  const previous = addMonths(monthOf(day), -1)
  const competence = dasDueDate(previous) >= day ? previous : monthOf(day)
  const entry = (await payrollWindow(deps, tenantId, competence)).find(
    candidate => candidate.proLaboreCents > 0,
  )
  if (!entry) {
    return null
  }
  return {
    estimate: money(proLaboreInss(Money.of(entry.proLaboreCents))),
    due: dasDueDate(competence),
  }
}

async function draftsOf(
  deps: Pick<Deps, 'invoices'>,
  tenantId: string,
  entityId: string,
) {
  const drafts = await deps.invoices.all(tenantId, {
    entityId,
    status: 'DRAFT',
  })
  return Promise.all(
    drafts.map(async (draft): Promise<CompanySummary['drafts'][number]> => {
      const client = await deps.invoices.findClient(tenantId, draft.clientId)
      return {
        id: draft.id,
        customer: client?.name ?? '',
        amount: money(draft.amount),
        recurring: draft.templateId !== null,
        issueOn: draft.issueOn,
      }
    }),
  )
}

async function unbilledOf(
  deps: Pick<Deps, 'transactions'>,
  tenantId: string,
  cash: readonly Account[],
  day: LocalDate,
) {
  const recent = await cashTransactions(deps, tenantId, cash, {
    from: addDays(day, -UNBILLED_DAYS),
    to: day,
  })
  return recent
    .filter(
      tx =>
        tx.amount.isPositive() &&
        tx.transferGroupId === null &&
        tx.invoiceId === null,
    )
    .map(tx => ({
      id: tx.id,
      payer: tx.description,
      amount: money(tx.amount),
      receivedOn: tx.bookedOn,
    }))
}

export function makeConsolidatedSummary(
  deps: Pick<
    Deps,
    'entities' | 'accounts' | 'transactions' | 'transfers' | 'clock'
  >,
) {
  return async function consolidatedSummary(
    tenantId: string,
  ): Promise<ConsolidatedSummary> {
    const month = monthOf(today(deps.clock.now()))
    const [personal, company, transfers] = await Promise.all([
      scopeOf(deps, tenantId, 'PF'),
      scopeOf(deps, tenantId, 'PJ'),
      deps.transfers.list(tenantId, monthInstants(month)),
    ])
    const cash = [...personal.accounts, ...company.accounts].filter(isCash)
    const moved = await cashTransactions(deps, tenantId, cash, {
      from: firstDay(month),
      to: lastDay(month),
    })
    const external = moved.filter(tx => tx.transferGroupId === null)
    const total = (scope: Scope) =>
      money(sum(scope.accounts.filter(isCash).map(account => account.balance)))
    return {
      personal: total(personal),
      company: total(company),
      externalIn: money(
        sum(external.filter(tx => tx.amount.isPositive()).map(tx => tx.amount)),
      ),
      externalOut: money(
        sum(external.filter(tx => tx.amount.isNegative()).map(tx => tx.amount)),
      ),
      transfers: transfers.map(transfer => ({
        id: transfer.id,
        kind: transfer.kind,
        amount: money(transfer.amount),
        on: today(transfer.at),
      })),
    }
  }
}
