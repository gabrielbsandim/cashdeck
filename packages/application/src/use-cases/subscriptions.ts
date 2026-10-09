import {
  type Account,
  addDays,
  detectRecurring,
  type EntityKind,
  groupByRecurrence,
  type LocalDate,
  Money,
  recurrenceKey,
  type RecurringCharge,
  summarizeCharges,
  type Transaction,
  ValidationError,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type SubscriptionsView, type SubscriptionView } from '@/dtos/insights'
import { type Recurrence, type RecurrenceStatus } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import {
  categoryIndex,
  flowEntries,
  insightScope,
  type InsightsDeps,
  percentChange,
} from '@/use-cases/insights'
import { addMonths, monthOf, required, today } from '@/use-cases/shared'

type SubscriptionDeps = InsightsDeps &
  Pick<Deps, 'recurrences' | 'ids' | 'accounts'>

// Enough months to see a charge three times even when one month was missed.
const HISTORY_DAYS = 200
// Days past the usual charge day before a missing charge counts as late.
const LATE_GRACE_DAYS = 3

function monthStatus(
  lastChargeOn: LocalDate | null,
  dayOfMonth: number,
  day: LocalDate,
): SubscriptionView['thisMonth'] {
  if (lastChargeOn !== null && monthOf(lastChargeOn) === monthOf(day)) {
    return 'PAID'
  }
  const late = Number(day.slice(8, 10)) > dayOfMonth + LATE_GRACE_DAYS
  return late ? 'LATE' : 'UPCOMING'
}

function priceOf(charge: RecurringCharge) {
  const previous = charge.previousAmount
  if (!previous) {
    return { previousAmount: null, priceChanged: false }
  }
  return {
    previousAmount: money(previous),
    priceChanged: previous.cents !== charge.amount.cents,
  }
}

function chargeView(
  charge: RecurringCharge,
  options: { id: string | null; kind: EntityKind; day: LocalDate },
): SubscriptionView {
  return {
    id: options.id,
    key: charge.key,
    entityKind: options.kind,
    name: charge.name,
    amount: money(charge.amount),
    ...priceOf(charge),
    dayOfMonth: charge.dayOfMonth,
    lastChargeOn: charge.lastChargeOn,
    thisMonth: monthStatus(charge.lastChargeOn, charge.dayOfMonth, options.day),
    accountId: charge.accountId,
    categoryId: charge.categoryId,
    transactionIds: [...charge.transactionIds],
  }
}

// A confirmed recurrence whose charges fell out of the history window.
function storedView(
  recurrence: Recurrence,
  kind: EntityKind,
  day: LocalDate,
): SubscriptionView {
  return {
    id: recurrence.id,
    key: recurrence.key,
    entityKind: kind,
    name: recurrence.name,
    amount: money(recurrence.amount),
    previousAmount: null,
    priceChanged: false,
    dayOfMonth: recurrence.dayOfMonth,
    lastChargeOn: recurrence.lastSeenOn,
    thisMonth: monthStatus(recurrence.lastSeenOn, recurrence.dayOfMonth, day),
    accountId: null,
    categoryId: null,
    transactionIds: [],
  }
}

type EntityCharges = {
  kind: EntityKind
  charges: readonly Transaction[]
  decided: readonly Recurrence[]
  day: LocalDate
}

function confirmedView(
  recurrence: Recurrence,
  groups: ReadonlyMap<string, Transaction[]>,
  context: EntityCharges,
) {
  const group = groups.get(recurrence.key)
  if (!group) {
    return {
      view: storedView(recurrence, context.kind, context.day),
      lastMonth: 0,
    }
  }
  const charge = summarizeCharges(recurrence.key, group)
  const lastMonth = addMonths(monthOf(context.day), -1)
  return {
    view: chargeView(charge, {
      id: recurrence.id,
      kind: context.kind,
      day: context.day,
    }),
    lastMonth: group
      .filter(transaction => monthOf(transaction.bookedOn) === lastMonth)
      .reduce((total, transaction) => total - transaction.amount.cents, 0),
  }
}

function entitySubscriptions(context: EntityCharges) {
  const groups = groupByRecurrence(context.charges)
  const confirmed = context.decided
    .filter(recurrence => recurrence.status === 'CONFIRMED')
    .map(recurrence => confirmedView(recurrence, groups, context))
  const known = new Set(context.decided.map(recurrence => recurrence.key))
  const suggestions = detectRecurring(context.charges, context.day)
    .filter(charge => !known.has(charge.key))
    .map(charge =>
      chargeView(charge, { id: null, kind: context.kind, day: context.day }),
    )
  return {
    items: confirmed.map(entry => entry.view),
    previousMonth: confirmed.reduce(
      (total, entry) => total + entry.lastMonth,
      0,
    ),
    suggestions,
  }
}

const byName = (a: SubscriptionView, b: SubscriptionView) =>
  a.dayOfMonth - b.dayOfMonth || a.name.localeCompare(b.name)

export function makeSubscriptions(deps: SubscriptionDeps) {
  async function expensesByEntity(
    tenantId: string,
    accounts: readonly Account[],
    day: LocalDate,
  ): Promise<Map<string, Transaction[]>> {
    const categories = await categoryIndex(deps, tenantId)
    const entries = await flowEntries(deps, tenantId, accounts, categories, {
      from: addDays(day, -HISTORY_DAYS),
      to: day,
    })
    const owner = new Map(
      accounts.map(account => [account.id, account.entityId]),
    )
    const byEntity = new Map<string, Transaction[]>()
    for (const entry of entries.filter(entry => entry.kind === 'EXPENSE')) {
      const entityId = owner.get(entry.transaction.accountId) as string
      byEntity.set(entityId, [
        ...(byEntity.get(entityId) ?? []),
        entry.transaction,
      ])
    }
    return byEntity
  }

  async function list(
    tenantId: string,
    kind?: EntityKind,
  ): Promise<SubscriptionsView> {
    const day = today(deps.clock.now())
    const scope = await insightScope(deps, tenantId, kind)
    const expenses = await expensesByEntity(tenantId, scope.accounts, day)
    const decided = await deps.recurrences.list(tenantId)
    const parts = scope.entities.map(entity =>
      entitySubscriptions({
        kind: entity.kind,
        charges: expenses.get(entity.id) ?? [],
        decided: decided.filter(r => r.entityId === entity.id),
        day,
      }),
    )
    const items = parts.flatMap(part => part.items)
    const monthly = items.reduce((total, item) => total + item.amount.cents, 0)
    const previousMonth = parts.reduce(
      (total, part) => total + part.previousMonth,
      0,
    )
    return {
      monthly: money(Money.of(monthly)),
      yearly: money(Money.of(monthly * 12)),
      previousMonth: money(Money.of(previousMonth)),
      changePercent: percentChange(monthly, previousMonth),
      items: items.sort(byName),
      suggestions: parts.flatMap(part => part.suggestions).sort(byName),
    }
  }

  async function decide(
    tenantId: string,
    transactionId: string,
    status: RecurrenceStatus,
  ): Promise<{ id: string }> {
    const transaction = required(
      await deps.transactions.findById(tenantId, transactionId),
      'Transaction',
    )
    const account = required(
      await deps.accounts.findById(tenantId, transaction.accountId),
      'Account',
    )
    const key = recurrenceKey(transaction)
    if (key === '' || !transaction.amount.isNegative()) {
      throw new ValidationError('This transaction cannot recur.')
    }
    const saved = await deps.recurrences.save({
      id: deps.ids.next(),
      tenantId,
      entityId: account.entityId,
      key,
      name: transaction.merchant ?? transaction.description,
      amount: transaction.amount.negate(),
      dayOfMonth: Number(transaction.bookedOn.slice(8, 10)),
      status,
      lastSeenOn: transaction.bookedOn,
    })
    return { id: saved.id }
  }

  async function remove(tenantId: string, id: string): Promise<{ id: string }> {
    const recurrence = required(
      await deps.recurrences.findById(tenantId, id),
      'Subscription',
    )
    await deps.recurrences.save({ ...recurrence, status: 'DISMISSED' })
    return { id }
  }

  return {
    list,
    confirm: (tenantId: string, transactionId: string) =>
      decide(tenantId, transactionId, 'CONFIRMED'),
    dismiss: (tenantId: string, transactionId: string) =>
      decide(tenantId, transactionId, 'DISMISSED'),
    remove,
  }
}
