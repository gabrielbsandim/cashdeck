import {
  addDays,
  type Bill,
  type BillStatus,
  CASH_ACCOUNT_TYPES,
  type FinancialEntity,
  type LocalDate,
  Money,
  recipientKeys,
  toCounterparty,
  ValidationError,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type FundingItemInput,
  type FundingItemView,
  type FundingPlan,
} from '@/dtos/home'
import { NotFoundError } from '@/errors/errors'
import { loadAutoDebit } from '@/use-cases/auto-debit'
import { dueAfter } from '@/use-cases/card-cycle'
import { type Deps } from '@/use-cases/deps'
import {
  addMonths,
  allPages,
  lastDay,
  monthOf,
  requireEntity,
  today,
} from '@/use-cases/shared'

const HISTORY_MONTHS = 6
const UPCOMING_DAYS = 30
const FUNDED: readonly BillStatus[] = ['OPEN', 'NEEDS_CONFIRMATION']
export const FUNDING_ITEMS_COLLECTION = 'funding-items'
// A larger Pix to a person is a planned payment, not the small ones the
// reserve is for.
const LOOSE_PIX_MAX_CENTS = 50_000
const MAX_ITEMS = 30
// A payee that sent nothing for longer than this has stopped billing.
const STALE_DAYS = 45

const sum = (amounts: readonly Money[]) =>
  amounts.reduce((total, amount) => total.add(amount), Money.zero())

const keyOf = (bill: Bill) => recipientKeys(bill).join('|')

// The history is an even number of months, so the median sits between two.
function median(values: readonly number[]): number {
  const sorted = [...values].sort((a, b) => a - b)
  const middle = sorted.length / 2
  return Math.round(
    ((sorted[middle - 1] as number) + (sorted[middle] as number)) / 2,
  )
}

// A payee that bills every month sends the next bill only days before it is
// due, so the last one stands in for it until it arrives.
function expectedBills(
  bills: readonly Bill[],
  day: LocalDate,
  end: LocalDate,
): Money[] {
  const byPayee = new Map<string, Bill[]>()
  for (const bill of bills) {
    byPayee.set(keyOf(bill), [...(byPayee.get(keyOf(bill)) ?? []), bill])
  }
  return [...byPayee.values()].flatMap(own => {
    const latest = [...own].sort((a, b) =>
      b.dueDate.localeCompare(a.dueDate),
    )[0] as Bill
    const current = latest.dueDate >= addDays(day, -STALE_DAYS)
    return current && dueAfter(latest.dueDate, day) <= end
      ? [latest.amount]
      : []
  })
}

// The small Pix sent to people in a typical month: a friend's share of a
// pizza, a tip. The median keeps one unusual month from setting the reserve.
async function loosePixReserve(
  deps: Pick<Deps, 'accounts' | 'transactions'>,
  tenantId: string,
  entity: FinancialEntity,
  day: LocalDate,
): Promise<Money> {
  const accounts = (await deps.accounts.listByEntity(tenantId, entity.id))
    .filter(account => CASH_ACCOUNT_TYPES.includes(account.type))
    .map(account => account.id)
  if (accounts.length === 0) {
    return Money.zero()
  }
  const current = monthOf(day)
  const first = addMonths(current, -HISTORY_MONTHS)
  const sent = await deps.transactions.all(tenantId, {
    accountIds: accounts,
    from: `${first}-01`,
    to: lastDay(addMonths(current, -1)),
  })
  const totals = new Map<string, number>()
  for (const tx of sent) {
    const person = toCounterparty(tx.counterparty)
    const loose =
      tx.amount.isNegative() && -tx.amount.cents <= LOOSE_PIX_MAX_CENTS
    const stranger = person?.length === 11 && person !== entity.taxId.value
    if (!stranger || !loose || tx.transferGroupId !== null) {
      continue
    }
    const month = monthOf(tx.bookedOn)
    totals.set(month, (totals.get(month) ?? 0) - tx.amount.cents)
  }
  const months = Array.from({ length: HISTORY_MONTHS }, (_, index) =>
    addMonths(first, index),
  )
  return Money.of(median(months.map(month => totals.get(month) ?? 0)))
}

type ItemDeps = Pick<Deps, 'documents' | 'ids'>

async function listItems(
  deps: Pick<Deps, 'documents'>,
  tenantId: string,
): Promise<FundingItemView[]> {
  const items = await deps.documents.list<FundingItemView>(
    tenantId,
    FUNDING_ITEMS_COLLECTION,
  )
  return [...items].sort((a, b) => a.dayOfMonth - b.dayOfMonth)
}

// What the Asaas balance pays a month, and what to send so it covers the next
// 30 days of bills, expected bills, fixed payments and loose Pix.
export function makeFundingPlan(
  deps: Pick<
    Deps,
    | 'entities'
    | 'bills'
    | 'documents'
    | 'funder'
    | 'clock'
    | 'accounts'
    | 'transactions'
  >,
) {
  async function balanceOf(tenantId: string, entityId: string) {
    try {
      return Money.of(await deps.funder.availableCents({ tenantId, entityId }))
    } catch {
      return null
    }
  }

  return async function fundingPlan(tenantId: string): Promise<FundingPlan> {
    const entity = await requireEntity(deps.entities, tenantId, 'PF')
    const day = today(deps.clock.now())
    const isAutoDebit = await loadAutoDebit(deps, tenantId)
    const bills = (
      await allPages(request =>
        deps.bills.list(tenantId, { entityId: entity.id }, request),
      )
    ).filter(bill => bill.status !== 'CANCELLED' && !isAutoDebit(bill))
    const current = monthOf(day)
    const first = bills
      .map(bill => monthOf(bill.dueDate))
      .reduce(
        (earliest, month) => (month < earliest ? month : earliest),
        current,
      )
    const floor = addMonths(current, 1 - HISTORY_MONTHS)
    const start = first > floor ? first : floor
    const months: FundingPlan['months'] = []
    for (let month = start; month <= current; month = addMonths(month, 1)) {
      const own = bills.filter(bill => monthOf(bill.dueDate) === month)
      months.push({ month, total: money(sum(own.map(bill => bill.amount))) })
    }
    const total = months.reduce((cents, month) => cents + month.total.cents, 0)
    const end = addDays(day, UPCOMING_DAYS)
    const upcoming = sum(
      bills
        .filter(
          bill =>
            FUNDED.includes(bill.status) &&
            bill.dueDate >= day &&
            bill.dueDate <= end,
        )
        .map(bill => bill.amount),
    )
    // Every day of the month falls within the next 30 days.
    const items = await listItems(deps, tenantId)
    const expected = sum([
      ...expectedBills(bills, day, end),
      ...items.map(item => Money.of(item.amount.cents)),
    ])
    const pixReserve = await loosePixReserve(deps, tenantId, entity, day)
    const balance = await balanceOf(tenantId, entity.id)
    const shortfall = upcoming
      .add(expected)
      .add(pixReserve)
      .subtract(balance ?? Money.zero())
    return {
      balance: balance && money(balance),
      monthlyAverage: money(Money.of(Math.round(total / months.length))),
      months,
      upcoming: money(upcoming),
      expected: money(expected),
      pixReserve: money(pixReserve),
      items,
      topUp: money(shortfall.isPositive() ? shortfall : Money.zero()),
    }
  }
}

export function makeFundingItems(deps: ItemDeps) {
  return {
    async add(
      tenantId: string,
      input: FundingItemInput,
    ): Promise<FundingItemView> {
      const items = await listItems(deps, tenantId)
      if (items.length >= MAX_ITEMS) {
        throw new ValidationError(`At most ${MAX_ITEMS} fixed payments.`)
      }
      const item: FundingItemView = {
        id: deps.ids.next(),
        name: input.name,
        amount: money(Money.of(input.amountCents)),
        dayOfMonth: input.dayOfMonth,
      }
      await deps.documents.put(
        tenantId,
        FUNDING_ITEMS_COLLECTION,
        item.id,
        item,
      )
      return item
    },

    async remove(tenantId: string, id: string): Promise<{ id: string }> {
      const found = await deps.documents.get<FundingItemView>(
        tenantId,
        FUNDING_ITEMS_COLLECTION,
        id,
      )
      if (!found) {
        throw new NotFoundError('Fixed payment')
      }
      await deps.documents.delete(tenantId, FUNDING_ITEMS_COLLECTION, id)
      return { id }
    },
  }
}
