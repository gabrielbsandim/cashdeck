import {
  type Account,
  addDays,
  type Bill,
  type Category,
  classifyFlow,
  creditUsedPercent,
  daysBetween,
  type EntityKind,
  type FinancialEntity,
  type FlowKind,
  isSettled,
  type LocalDate,
  Money,
  openBillOf,
  type Transaction,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type InsightPeriod,
  type InsightsOverview,
  type InsightsOverviewQuery,
} from '@/dtos/insights'
import { cardDues, type CardDues } from '@/use-cases/card-cycle'
import { type Deps } from '@/use-cases/deps'
import {
  addMonths,
  firstDay,
  lastDay,
  monthOf,
  requireEntity,
  today,
} from '@/use-cases/shared'

export type InsightsDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'transactions'
  | 'categories'
  | 'bills'
  | 'cardBills'
  | 'clock'
>

export type DayRange = { from: LocalDate; to: LocalDate }

const FLOW_ACCOUNT_TYPES = new Set<Account['type']>([
  'CHECKING',
  'SAVINGS',
  'WALLET',
  'CREDIT_CARD',
])
const TOP_MERCHANTS = 3
const BILLS_DUE_DAYS = 7
const BILL_PAGE = { limit: 200 }

export type FlowEntry = {
  transaction: Transaction
  kind: FlowKind
  // Positive cents: what came in for income, what went out for an expense.
  cents: number
}

export type InsightScope = {
  entities: FinancialEntity[]
  accounts: Account[]
}

function monthsBack(day: LocalDate, count: number) {
  const month = monthOf(day)
  const first = addMonths(month, -(count - 1))
  return {
    range: { from: firstDay(first), to: day },
    previousRange: {
      from: firstDay(addMonths(first, -count)),
      to: lastDay(addMonths(month, -count)),
    },
  }
}

export function periodRanges(
  period: InsightPeriod,
  day: LocalDate,
): { range: DayRange; previousRange: DayRange } {
  switch (period) {
    case '1w':
      return {
        range: { from: addDays(day, -6), to: day },
        previousRange: { from: addDays(day, -13), to: addDays(day, -7) },
      }
    case '1m':
      return monthsBack(day, 1)
    case '6m':
      return monthsBack(day, 6)
    case '1y':
      return monthsBack(day, 12)
  }
}

const earlier = (a: LocalDate, b: LocalDate) => (a < b ? a : b)

const inRange = (day: LocalDate, range: DayRange) =>
  day >= range.from && day <= range.to

export const cents = (value: number) => money(Money.of(value))

export function percentChange(current: number, previous: number) {
  if (previous === 0) {
    return null
  }
  return Math.round(((current - previous) * 100) / previous)
}

export async function insightScope(
  deps: Pick<InsightsDeps, 'entities' | 'accounts'>,
  tenantId: string,
  kind: EntityKind | undefined,
): Promise<InsightScope> {
  const entities = kind
    ? [await requireEntity(deps.entities, tenantId, kind)]
    : await deps.entities.list(tenantId)
  const ids = new Set(entities.map(entity => entity.id))
  const accounts = (await deps.accounts.list(tenantId)).filter(
    account =>
      ids.has(account.entityId) &&
      FLOW_ACCOUNT_TYPES.has(account.type) &&
      account.balance.currency === 'BRL',
  )
  return { entities, accounts }
}

export async function flowEntries(
  deps: Pick<InsightsDeps, 'transactions'>,
  tenantId: string,
  accounts: readonly Account[],
  categories: ReadonlyMap<string, Category>,
  range: DayRange,
): Promise<FlowEntry[]> {
  if (accounts.length === 0) {
    return []
  }
  const types = new Map(accounts.map(account => [account.id, account.type]))
  const transactions = await deps.transactions.all(tenantId, {
    accountIds: accounts.map(account => account.id),
    ...range,
  })
  const kinds = classifyFlow(
    transactions.map(transaction => ({
      transaction,
      accountType: types.get(transaction.accountId) as Account['type'],
      categoryKey: categories.get(transaction.categoryId ?? '')?.key ?? null,
    })),
  )
  return transactions.map(transaction => ({
    transaction,
    kind: kinds.get(transaction.id) as FlowKind,
    cents: Math.abs(transaction.amount.cents),
  }))
}

export const totalOf = (entries: readonly FlowEntry[]) =>
  entries.reduce((total, entry) => total + entry.cents, 0)

export function within(
  entries: readonly FlowEntry[],
  kind: FlowKind,
  range: DayRange,
): FlowEntry[] {
  return entries.filter(
    entry => entry.kind === kind && inRange(entry.transaction.bookedOn, range),
  )
}

function cumulative(entries: readonly FlowEntry[], range: DayRange) {
  const byDay = new Map<LocalDate, number>()
  for (const entry of entries) {
    const day = entry.transaction.bookedOn
    byDay.set(day, (byDay.get(day) ?? 0) + entry.cents)
  }
  const points: InsightsOverview['spend']['series'] = []
  let running = 0
  for (let day = range.from; day <= range.to; day = addDays(day, 1)) {
    running += byDay.get(day) ?? 0
    points.push({ day, cumulative: cents(running) })
  }
  return points
}

export function groupBy(
  entries: readonly FlowEntry[],
  keyOf: (transaction: Transaction) => string,
): Map<string, { total: number; count: number }> {
  const groups = new Map<string, { total: number; count: number }>()
  for (const entry of entries) {
    const key = keyOf(entry.transaction)
    const group = groups.get(key) ?? { total: 0, count: 0 }
    groups.set(key, {
      total: group.total + entry.cents,
      count: group.count + 1,
    })
  }
  return groups
}

const byTotal = <T extends { total: number }>(a: T, b: T) => b.total - a.total

const merchantOf = (transaction: Transaction) =>
  transaction.merchant ?? transaction.description

function topMerchants(expenses: readonly FlowEntry[]) {
  return [...groupBy(expenses, merchantOf)]
    .map(([name, group]) => ({ name, ...group }))
    .sort(byTotal)
    .slice(0, TOP_MERCHANTS)
    .map(item => ({
      name: item.name,
      total: cents(item.total),
      count: item.count,
    }))
}

export const UNCATEGORIZED = ''

export const categoryOf = (transaction: Transaction) =>
  transaction.categoryId ?? UNCATEGORIZED

function categoryItems(
  expenses: readonly FlowEntry[],
  previous: readonly FlowEntry[],
  categories: ReadonlyMap<string, Category>,
): InsightsOverview['categories'] {
  const total = totalOf(expenses)
  const before = groupBy(previous, categoryOf)
  const items = [...groupBy(expenses, categoryOf)]
    .map(([id, group]) => ({ id, total: group.total }))
    .sort(byTotal)
    .map(({ id, total: spent }) => {
      const category = categories.get(id)
      return {
        categoryId: id === UNCATEGORIZED ? null : id,
        key: category?.key ?? null,
        name: category?.name ?? null,
        icon: category?.icon ?? null,
        total: cents(spent),
        sharePercent: Math.round((spent * 100) / total),
        changePercent: percentChange(spent, before.get(id)?.total ?? 0),
      }
    })
  return { total: cents(total), items }
}

function earliestDue(
  cards: readonly Account[],
  dues: CardDues,
  day: LocalDate,
) {
  const dates = cards
    .map(card => dues.get(card.id) ?? null)
    .filter((due): due is LocalDate => due !== null)
    .sort()
  return dates.find(due => due >= day) ?? dates.at(0) ?? null
}

export function cardsSummary(
  accounts: readonly Account[],
  dues: CardDues,
  day: LocalDate,
): InsightsOverview['cards'] {
  const cards = accounts.filter(account => account.type === 'CREDIT_CARD')
  if (cards.length === 0) {
    return null
  }
  const owed = cards.reduce((total, card) => total + openBillOf(card).cents, 0)
  const lines = cards.flatMap(card => (card.credit ? [card.credit] : []))
  const limit = lines.reduce((total, line) => total + line.limit.cents, 0)
  const available = lines.reduce(
    (total, line) => total + line.available.cents,
    0,
  )
  const withLimit = lines.length > 0
  return {
    bill: cents(owed),
    dueOn: earliestDue(cards, dues, day),
    count: cards.length,
    limit: withLimit ? cents(limit) : null,
    used: withLimit ? cents(limit - available) : null,
    usedPercent: withLimit
      ? creditUsedPercent({
          limit: Money.of(limit),
          available: Money.of(available),
          closesOn: null,
          dueOn: null,
          brand: null,
          openBill: null,
        })
      : null,
  }
}

export async function billsDueIn(
  deps: Pick<InsightsDeps, 'bills'>,
  tenantId: string,
  entities: readonly FinancialEntity[],
  range: DayRange,
  keep: (bill: Bill) => boolean,
) {
  const due = []
  for (const entity of entities) {
    const page = await deps.bills.list(
      tenantId,
      { entityId: entity.id },
      BILL_PAGE,
    )
    due.push(
      ...page.items.filter(bill => keep(bill) && inRange(bill.dueDate, range)),
    )
  }
  return due
}

export const openBillsDue = (
  deps: Pick<InsightsDeps, 'bills'>,
  tenantId: string,
  entities: readonly FinancialEntity[],
  range: DayRange,
) => billsDueIn(deps, tenantId, entities, range, bill => !isSettled(bill))

export async function categoryIndex(
  deps: Pick<InsightsDeps, 'categories'>,
  tenantId: string,
): Promise<Map<string, Category>> {
  const categories = await deps.categories.list(tenantId)
  return new Map(categories.map(category => [category.id, category]))
}

export function makeInsightsOverview(deps: InsightsDeps) {
  return async function insightsOverview(
    tenantId: string,
    query: InsightsOverviewQuery,
  ): Promise<InsightsOverview> {
    const day = today(deps.clock.now())
    const { range, previousRange } = periodRanges(query.period, day)
    const scope = await insightScope(deps, tenantId, query.entity)
    const categories = await categoryIndex(deps, tenantId)
    const entries = await flowEntries(
      deps,
      tenantId,
      scope.accounts,
      categories,
      { from: previousRange.from, to: range.to },
    )
    const sameSpan = {
      from: previousRange.from,
      to: earlier(
        addDays(previousRange.from, daysBetween(range.from, range.to)),
        previousRange.to,
      ),
    }
    const expenses = within(entries, 'EXPENSE', range)
    const previousExpenses = within(entries, 'EXPENSE', sameSpan)
    const total = totalOf(expenses)
    const previous = totalOf(previousExpenses)
    const income = totalOf(within(entries, 'INCOME', range))
    const bills = await openBillsDue(deps, tenantId, scope.entities, {
      from: day,
      to: addDays(day, BILLS_DUE_DAYS),
    })
    return {
      period: query.period,
      range,
      previousRange,
      spend: {
        total: cents(total),
        previous: cents(previous),
        changePercent: percentChange(total, previous),
        series: cumulative(expenses, range),
        previousSeries: cumulative(
          within(entries, 'EXPENSE', previousRange),
          previousRange,
        ),
        topMerchants: topMerchants(expenses),
      },
      categories: categoryItems(expenses, previousExpenses, categories),
      flow: {
        income: cents(income),
        expenses: cents(total),
        result: cents(income - total),
      },
      cards: cardsSummary(
        scope.accounts,
        await cardDues(deps, tenantId, scope.accounts, day),
        day,
      ),
      billsDue: {
        days: BILLS_DUE_DAYS,
        total: cents(bills.reduce((sum, bill) => sum + bill.amount.cents, 0)),
        count: bills.length,
      },
    }
  }
}
