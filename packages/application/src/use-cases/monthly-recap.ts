import {
  buildMonthlyRecap,
  type Category,
  type CategoryShift,
  type CategorySpend,
  type CentsChange,
  closedMonthOf,
  type EntityKind,
  Money,
  type MonthlyRecapFacts,
  type RecapSubscription,
  requireClosedMonth,
} from '@cashdeck/domain'
import {
  type MonthlyRecap,
  type MonthlyRecapQuery,
  type MonthlyRecapRun,
} from '@/dtos/monthly-recap'
import { type DeviceLocale } from '@/ports/alerts'
import { formatMoney } from '@/use-cases/alert-events'
import { type Deps } from '@/use-cases/deps'
import {
  categoryIndex,
  categoryOf,
  cents,
  type DayRange,
  type FlowEntry,
  flowEntries,
  groupBy,
  insightScope,
  type InsightsDeps,
  totalOf,
  within,
} from '@/use-cases/insights'
import { type RecapFigures, writeStory } from '@/use-cases/monthly-recap-story'
import { makeNetWorthFromBalancesAndSnapshots } from '@/use-cases/net-worth'
import {
  addMonths,
  firstDay,
  lastDay,
  monthOf,
  today,
} from '@/use-cases/shared'
import { makeSubscriptions } from '@/use-cases/subscriptions'

type RecapDeps = InsightsDeps &
  Pick<
    Deps,
    | 'recurrences'
    | 'ids'
    | 'investments'
    | 'llm'
    | 'documents'
    | 'devices'
    | 'alerts'
  >

export const MONTHLY_RECAP_COLLECTION = 'monthly-recaps'
// The longest net worth history the use case serves.
const NET_WORTH_MONTHS = 24
const DEFAULT_LOCALE: DeviceLocale = 'pt'

const monthRange = (month: string): DayRange => ({
  from: firstDay(month),
  to: lastDay(month),
})

const changeView = (change: CentsChange) => ({
  amount: cents(change.cents),
  percent: change.percent,
})

function flowOf(entries: readonly FlowEntry[], month: string) {
  const range = monthRange(month)
  return {
    income: totalOf(within(entries, 'INCOME', range)),
    expenses: totalOf(within(entries, 'EXPENSE', range)),
  }
}

function spendOf(
  entries: readonly FlowEntry[],
  month: string,
  categories: ReadonlyMap<string, Category>,
): CategorySpend[] {
  return [...groupBy(within(entries, 'EXPENSE', monthRange(month)), categoryOf)]
    .filter(([id]) => categories.has(id))
    .map(([categoryId, group]) => ({ categoryId, cents: group.total }))
}

function figures(
  facts: MonthlyRecapFacts,
  categories: ReadonlyMap<string, Category>,
  entity: EntityKind | undefined,
): RecapFigures {
  const ref = (categoryId: string) => {
    const category = categories.get(categoryId) as Category
    return {
      categoryId,
      key: category.key,
      name: category.name,
      icon: category.icon,
    }
  }
  const shift = (item: CategoryShift) => ({
    ...ref(item.categoryId),
    total: cents(item.cents),
    previous: cents(item.previousCents),
    change: changeView(item.change),
  })
  const subscription = (item: RecapSubscription) => ({
    key: item.key,
    name: item.name,
    amount: cents(item.cents),
  })
  const flow = (value: MonthlyRecapFacts['flow']) => ({
    income: cents(value.income),
    expenses: cents(value.expenses),
    net: cents(value.net),
  })
  const top = facts.topCategory
  const netWorth = facts.netWorth
  return {
    month: facts.month,
    entity: entity ?? null,
    flow: flow(facts.flow),
    previousFlow: flow(facts.previousFlow),
    incomeChange: changeView(facts.incomeChange),
    expensesChange: changeView(facts.expensesChange),
    savings: {
      percent: facts.savingsPercent,
      previousPercent: facts.previousSavingsPercent,
    },
    topCategory: top && {
      ...ref(top.categoryId),
      total: cents(top.cents),
      sharePercent: top.sharePercent,
    },
    changes: { rose: facts.rose.map(shift), fell: facts.fell.map(shift) },
    subscriptions: {
      started: facts.started.map(subscription),
      stopped: facts.stopped.map(subscription),
    },
    netWorth: netWorth && {
      total: cents(netWorth.end),
      change: changeView(netWorth.change),
    },
  }
}

const isQuiet = (recap: MonthlyRecap) =>
  recap.flow.income.cents === 0 && recap.flow.expenses.cents === 0

export function makeMonthlyRecap(deps: RecapDeps) {
  const subscriptions = makeSubscriptions(deps)
  const netWorth = makeNetWorthFromBalancesAndSnapshots(deps)

  async function localeOf(
    tenantId: string,
    asked: DeviceLocale | undefined,
  ): Promise<DeviceLocale> {
    if (asked) {
      return asked
    }
    const [latest] = (await deps.devices.list(tenantId)).sort(
      (a, b) => b.lastSeenAt.getTime() - a.lastSeenAt.getTime(),
    )
    return latest?.locale ?? DEFAULT_LOCALE
  }

  async function subscribed(
    tenantId: string,
    entity: EntityKind | undefined,
  ): Promise<RecapSubscription[]> {
    const view = await subscriptions.list(tenantId, entity)
    return view.items.map(item => ({
      key: item.key,
      name: item.name,
      cents: item.amount.cents,
      chargedMonths: item.charges.map(charge => monthOf(charge.bookedOn)),
    }))
  }

  async function monthEnds(
    tenantId: string,
    entity: EntityKind | undefined,
    month: string,
  ) {
    const view = await netWorth(tenantId, { entity, months: NET_WORTH_MONTHS })
    const totalOn = (at: string) =>
      view.series.find(point => point.on === lastDay(at))?.total.cents
    const end = totalOn(month)
    const previousEnd = totalOn(addMonths(month, -1))
    if (end === undefined || previousEnd === undefined) {
      return null
    }
    return { end, previousEnd }
  }

  async function compute(
    tenantId: string,
    month: string,
    entity: EntityKind | undefined,
  ): Promise<RecapFigures> {
    const previous = addMonths(month, -1)
    const scope = await insightScope(deps, tenantId, entity)
    const categories = await categoryIndex(deps, tenantId)
    const entries = await flowEntries(
      deps,
      tenantId,
      scope.accounts,
      categories,
      { from: firstDay(previous), to: lastDay(month) },
    )
    const facts = buildMonthlyRecap({
      month,
      flow: flowOf(entries, month),
      previousFlow: flowOf(entries, previous),
      categories: spendOf(entries, month, categories),
      previousCategories: spendOf(entries, previous, categories),
      subscriptions: await subscribed(tenantId, entity),
      netWorth: await monthEnds(tenantId, entity, month),
    })
    return figures(facts, categories, entity)
  }

  // A recap the AI wrote is kept; a template one is rebuilt on the next read,
  // so a model that was down gets another chance.
  async function get(
    tenantId: string,
    month: string,
    query: MonthlyRecapQuery,
  ): Promise<MonthlyRecap> {
    requireClosedMonth(month, today(deps.clock.now()))
    const locale = await localeOf(tenantId, query.locale)
    const id = `${query.entity ?? 'ALL'}:${month}:${locale}`
    const stored = await deps.documents.get<MonthlyRecap>(
      tenantId,
      MONTHLY_RECAP_COLLECTION,
      id,
    )
    if (stored) {
      return stored
    }
    const recap = await compute(tenantId, month, query.entity)
    const story = await writeStory(deps.llm, recap, locale)
    const view: MonthlyRecap = {
      ...recap,
      story: { ...story, locale },
      generatedAt: deps.clock.now().toISOString(),
    }
    if (story.source === 'AI') {
      await deps.documents.put(tenantId, MONTHLY_RECAP_COLLECTION, id, view)
    }
    return view
  }

  return {
    get,

    latest(tenantId: string, query: MonthlyRecapQuery): Promise<MonthlyRecap> {
      return get(tenantId, closedMonthOf(today(deps.clock.now())), query)
    },

    // Day 1: the personal recap of the month that closed, one push per month.
    async run(tenantId: string): Promise<MonthlyRecapRun> {
      const month = closedMonthOf(today(deps.clock.now()))
      const personal = await deps.entities.findByKind(tenantId, 'PF')
      if (!personal) {
        return { month, sent: false }
      }
      const recap = await get(tenantId, month, { entity: 'PF' })
      if (isQuiet(recap)) {
        return { month, sent: false }
      }
      const alert = await deps.alerts.emit({
        tenantId,
        type: 'MONTHLY_RECAP',
        entityId: personal.id,
        data: {
          month,
          entity: 'PF',
          income: formatMoney(Money.of(recap.flow.income.cents)),
          expenses: formatMoney(Money.of(recap.flow.expenses.cents)),
        },
        dedupeKey: `MONTHLY_RECAP:${month}`,
      })
      return { month, sent: alert !== null }
    },
  }
}
