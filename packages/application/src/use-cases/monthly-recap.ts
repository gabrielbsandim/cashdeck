import {
  buildMonthlyRecap,
  type Category,
  type CategoryShift,
  type CategorySpend,
  type CentsChange,
  closedMonthOf,
  ENTITY_KINDS,
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
// A template story waits this long before the model gets another try.
const TEMPLATE_RETRY_MS = 60 * 60 * 1000

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

function isFresh(recap: MonthlyRecap, now: Date): boolean {
  if (recap.story.source === 'AI') {
    return true
  }
  return now.getTime() - Date.parse(recap.generatedAt) < TEMPLATE_RETRY_MS
}

// The personal push keeps the key it had before the company got its own.
const recapDedupeKey = (entity: EntityKind, month: string) =>
  entity === 'PF'
    ? `MONTHLY_RECAP:${month}`
    : `MONTHLY_RECAP:${entity}:${month}`

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

  // A recap the AI wrote is kept for good; a template one only for a while,
  // so a model that was down gets another chance without a call per read.
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
    const now = deps.clock.now()
    if (stored && isFresh(stored, now)) {
      return stored
    }
    const recap = await compute(tenantId, month, query.entity)
    const story = await writeStory(deps.llm, recap, locale)
    const view: MonthlyRecap = {
      ...recap,
      story: { ...story, locale },
      generatedAt: now.toISOString(),
    }
    await deps.documents.put(tenantId, MONTHLY_RECAP_COLLECTION, id, view)
    return view
  }

  async function push(
    tenantId: string,
    month: string,
    kind: EntityKind,
  ): Promise<boolean> {
    const entity = await deps.entities.findByKind(tenantId, kind)
    if (!entity) {
      return false
    }
    const recap = await get(tenantId, month, { entity: kind })
    if (isQuiet(recap)) {
      return false
    }
    const alert = await deps.alerts.emit({
      tenantId,
      type: 'MONTHLY_RECAP',
      entityId: entity.id,
      data: {
        month,
        entity: kind,
        income: formatMoney(Money.of(recap.flow.income.cents)),
        expenses: formatMoney(Money.of(recap.flow.expenses.cents)),
      },
      dedupeKey: recapDedupeKey(kind, month),
    })
    return alert !== null
  }

  return {
    get,

    latest(tenantId: string, query: MonthlyRecapQuery): Promise<MonthlyRecap> {
      return get(tenantId, closedMonthOf(today(deps.clock.now())), query)
    },

    // Day 1: the recap of the month that closed, one push per entity and
    // month, for each entity that moved money in it.
    async run(tenantId: string): Promise<MonthlyRecapRun> {
      const month = closedMonthOf(today(deps.clock.now()))
      const entities: EntityKind[] = []
      for (const kind of ENTITY_KINDS) {
        if (await push(tenantId, month, kind)) {
          entities.push(kind)
        }
      }
      return { month, sent: entities.length > 0, entities }
    },
  }
}
