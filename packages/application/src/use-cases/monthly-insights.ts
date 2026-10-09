import {
  type Account,
  CASH_ACCOUNT_TYPES,
  type Category,
  committedByMonth,
  type EntityKind,
  type LocalDate,
} from '@cashdeck/domain'
import {
  type Insight,
  type MonthlyInsights,
  type MonthlyInsightsQuery,
  type SubscriptionsView,
} from '@/dtos/insights'
import { type Deps } from '@/use-cases/deps'
import {
  billsDueIn,
  categoryIndex,
  categoryOf,
  cents,
  type DayRange,
  type FlowEntry,
  flowEntries,
  groupBy,
  insightScope,
  type InsightScope,
  type InsightsDeps,
  openBillsDue,
  totalOf,
  UNCATEGORIZED,
  within,
} from '@/use-cases/insights'
import { cardDues, type CardDues } from '@/use-cases/card-cycle'
import { activePlans } from '@/use-cases/installments'
import {
  addMonths,
  firstDay,
  lastDay,
  monthInstants,
  monthOf,
  today,
} from '@/use-cases/shared'
import { makeSubscriptions } from '@/use-cases/subscriptions'

type MonthlyDeps = InsightsDeps &
  Pick<Deps, 'recurrences' | 'ids' | 'transfers'>

// Months behind the chosen one that make the "usual" level.
const AVERAGE_MONTHS = 3
const TOP_CHANGES = 3
const MAX_INSIGHTS = 3
const ABOVE_AVERAGE_PERCENT = 20
const ABOVE_AVERAGE_CENTS = 5_000
const SAVINGS_GAP_POINTS = 5

const monthRange = (month: string): DayRange => ({
  from: firstDay(month),
  to: lastDay(month),
})

const spanOf = (from: string, to: string): DayRange => ({
  from: firstDay(from),
  to: lastDay(to),
})

const percentOf = (part: number, whole: number) =>
  whole > 0 ? Math.round((part * 100) / whole) : null

function monthFlow(entries: readonly FlowEntry[], month: string) {
  const range = monthRange(month)
  const income = totalOf(within(entries, 'INCOME', range))
  const expenses = totalOf(within(entries, 'EXPENSE', range))
  return { month, income, expenses, result: income - expenses }
}

function averageOf(values: readonly (number | null)[]) {
  const known = values.filter((value): value is number => value !== null)
  if (known.length === 0) {
    return null
  }
  return Math.round(known.reduce((sum, value) => sum + value, 0) / known.length)
}

type CategoryChange = MonthlyInsights['changes']['rose'][number]

function categoryChanges(
  entries: readonly FlowEntry[],
  month: string,
  categories: ReadonlyMap<string, Category>,
): { rose: CategoryChange[]; fell: CategoryChange[] } {
  const now = groupBy(within(entries, 'EXPENSE', monthRange(month)), categoryOf)
  const before = groupBy(
    within(
      entries,
      'EXPENSE',
      spanOf(addMonths(month, -AVERAGE_MONTHS), addMonths(month, -1)),
    ),
    categoryOf,
  )
  const ids = new Set([...now.keys(), ...before.keys()])
  ids.delete(UNCATEGORIZED)
  const changes = [...ids]
    .filter(id => categories.has(id))
    .map(id => {
      const category = categories.get(id) as Category
      const total = now.get(id)?.total ?? 0
      const average = Math.round((before.get(id)?.total ?? 0) / AVERAGE_MONTHS)
      return {
        categoryId: id,
        key: category.key,
        name: category.name,
        icon: category.icon,
        total: cents(total),
        average: cents(average),
        delta: cents(total - average),
      }
    })
  return {
    rose: changes
      .filter(change => change.delta.cents > 0)
      .sort((a, b) => b.delta.cents - a.delta.cents)
      .slice(0, TOP_CHANGES),
    fell: changes
      .filter(change => change.delta.cents < 0)
      .sort((a, b) => a.delta.cents - b.delta.cents)
      .slice(0, TOP_CHANGES),
  }
}

const isCash = (account: Account) =>
  CASH_ACCOUNT_TYPES.includes(account.type) && !account.isReserve

// What a card still owes on a bill due within the month, or of unknown date.
function cardBillDue(
  accounts: readonly Account[],
  dues: CardDues,
  range: DayRange,
) {
  return accounts
    .filter(account => account.type === 'CREDIT_CARD')
    .filter(card => {
      const due = dues.get(card.id) ?? null
      return due === null || due <= range.to
    })
    .reduce((total, card) => total + Math.max(0, -card.balance.cents), 0)
}

type MonthContext = {
  tenantId: string
  day: LocalDate
  month: string
  scope: InsightScope
  entries: readonly FlowEntry[]
  categories: ReadonlyMap<string, Category>
}

export function makeMonthlyInsights(deps: MonthlyDeps) {
  const subscriptions = makeSubscriptions(deps)

  async function fixedCost(
    context: MonthContext,
    subscribed: SubscriptionsView,
    income: number,
  ): Promise<MonthlyInsights['fixedCost']> {
    const installments = totalOf(
      within(context.entries, 'EXPENSE', monthRange(context.month)).filter(
        entry => entry.transaction.installment !== null,
      ),
    )
    const due = await billsDueIn(
      deps,
      context.tenantId,
      context.scope.entities,
      monthRange(context.month),
      bill => bill.status !== 'CANCELLED',
    )
    const bills = due.reduce((sum, bill) => sum + bill.amount.cents, 0)
    const total = subscribed.monthly.cents + installments + bills
    return {
      subscriptions: subscribed.monthly,
      installments: cents(installments),
      bills: cents(bills),
      total: cents(total),
      income: cents(income),
      sharePercent: percentOf(total, income),
    }
  }

  async function leftThisMonth(
    context: MonthContext,
  ): Promise<MonthlyInsights['leftThisMonth']> {
    if (context.month !== monthOf(context.day)) {
      return null
    }
    const rest = { from: context.day, to: lastDay(context.month) }
    const balance = context.scope.accounts
      .filter(isCash)
      .reduce((sum, account) => sum + account.balance.cents, 0)
    const bills = await openBillsDue(
      deps,
      context.tenantId,
      context.scope.entities,
      rest,
    )
    const billsDue = bills.reduce((sum, bill) => sum + bill.amount.cents, 0)
    const dues = await cardDues(
      deps,
      context.tenantId,
      context.scope.accounts,
      context.day,
    )
    const cardBill = cardBillDue(context.scope.accounts, dues, rest)
    return {
      balance: cents(balance),
      billsDue: cents(billsDue),
      cardBill: cents(cardBill),
      left: cents(balance - billsDue - cardBill),
    }
  }

  async function companyToPersonal(
    context: MonthContext,
  ): Promise<MonthlyInsights['companyToPersonal']> {
    const companies = new Set(
      context.scope.entities
        .filter(entity => entity.kind === 'PJ')
        .map(entity => entity.id),
    )
    if (companies.size === 0) {
      return null
    }
    const transfers = await deps.transfers.list(
      context.tenantId,
      monthInstants(context.month),
    )
    const companyAccounts = new Set(
      context.scope.accounts
        .filter(account => companies.has(account.entityId))
        .map(account => account.id),
    )
    const taxes = within(
      context.entries,
      'EXPENSE',
      monthRange(context.month),
    ).filter(
      entry =>
        companyAccounts.has(entry.transaction.accountId) &&
        context.categories.get(categoryOf(entry.transaction))?.key === 'taxes',
    )
    return {
      transfers: cents(
        transfers.reduce((sum, transfer) => sum + transfer.amount.cents, 0),
      ),
      taxes: cents(totalOf(taxes)),
    }
  }

  async function committedNextMonth(
    context: MonthContext,
    kind: EntityKind | undefined,
  ): Promise<Insight[]> {
    if (context.month !== monthOf(context.day)) {
      return []
    }
    const { plans } = await activePlans(deps, context.tenantId, kind)
    const next = addMonths(context.month, 1)
    const [committed] = committedByMonth(plans, next, 1)
    const amount = (committed as { amount: { cents: number } }).amount.cents
    if (amount === 0) {
      return []
    }
    return [
      {
        type: 'INSTALLMENTS_COMMITTED',
        tone: 'NEUTRAL',
        month: next,
        amount: cents(amount),
      },
    ]
  }

  function aboveAverage(rose: readonly CategoryChange[]): Insight[] {
    return rose
      .filter(change => change.average.cents > 0)
      .filter(change => change.delta.cents >= ABOVE_AVERAGE_CENTS)
      .map(change => ({
        change,
        percent: Math.round((change.delta.cents * 100) / change.average.cents),
      }))
      .filter(({ percent }) => percent >= ABOVE_AVERAGE_PERCENT)
      .slice(0, 1)
      .map(({ change, percent }) => ({
        type: 'CATEGORY_ABOVE_AVERAGE',
        tone: 'NEGATIVE',
        categoryId: change.categoryId,
        name: change.name,
        percent,
        amount: change.delta,
      }))
  }

  function savingsRate(
    percent: number | null,
    averagePercent: number | null,
  ): Insight[] {
    if (percent === null || averagePercent === null) {
      return []
    }
    if (Math.abs(percent - averagePercent) < SAVINGS_GAP_POINTS) {
      return []
    }
    return [
      {
        type: 'SAVINGS_RATE',
        tone: percent > averagePercent ? 'POSITIVE' : 'NEGATIVE',
        percent,
        averagePercent,
      },
    ]
  }

  function priceUp(subscribed: SubscriptionsView): Insight[] {
    return subscribed.items
      .filter(
        item =>
          item.previousAmount !== null &&
          item.amount.cents > item.previousAmount.cents,
      )
      .slice(0, 1)
      .map(item => ({
        type: 'SUBSCRIPTION_PRICE_UP',
        tone: 'NEGATIVE',
        name: item.name,
        amount: item.amount,
        previousAmount: item.previousAmount as SubscriptionsView['monthly'],
      }))
  }

  return async function monthlyInsights(
    tenantId: string,
    query: MonthlyInsightsQuery,
  ): Promise<MonthlyInsights> {
    const day = today(deps.clock.now())
    const month = query.month ?? monthOf(day)
    const first = addMonths(month, -(query.months - 1))
    const scope = await insightScope(deps, tenantId, query.entity)
    const categories = await categoryIndex(deps, tenantId)
    const entries = await flowEntries(
      deps,
      tenantId,
      scope.accounts,
      categories,
      spanOf(first, month),
    )
    const context = { tenantId, day, month, scope, entries, categories }
    const months = Array.from({ length: query.months }, (_, index) =>
      monthFlow(entries, addMonths(first, index)),
    )
    const trend = months.map(item => ({
      month: item.month,
      percent: percentOf(item.result, item.income),
    }))
    const latest = months.at(-1) as (typeof months)[number]
    const current = percentOf(latest.result, latest.income)
    const averagePercent = averageOf(
      trend.slice(-1 - AVERAGE_MONTHS, -1).map(item => item.percent),
    )
    const changes = categoryChanges(entries, month, categories)
    const subscribed = await subscriptions.list(tenantId, query.entity)
    const insights = [
      ...aboveAverage(changes.rose),
      ...(await committedNextMonth(context, query.entity)),
      ...savingsRate(current, averagePercent),
      ...priceUp(subscribed),
    ].slice(0, MAX_INSIGHTS)
    return {
      month,
      months: months.map(item => ({
        month: item.month,
        income: cents(item.income),
        expenses: cents(item.expenses),
        result: cents(item.result),
      })),
      savings: { percent: current, averagePercent, trend },
      changes,
      fixedCost: await fixedCost(context, subscribed, latest.income),
      leftThisMonth: await leftThisMonth(context),
      companyToPersonal: await companyToPersonal(context),
      insights,
    }
  }
}
