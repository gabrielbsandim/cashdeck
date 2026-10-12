import {
  type Account,
  addDays,
  type Bill,
  CASH_ACCOUNT_TYPES,
  type BudgetLeft,
  daysBetween,
  type EntityKind,
  expectedIncome,
  type FinancialEntity,
  isCardBillPayment,
  isSettled,
  type LocalDate,
  Money,
  monthlyDatesBetween,
  type Obligation,
  recurrenceKey,
  safeToSpend,
  spendingWindow,
  type Transaction,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type FundingItemView } from '@/dtos/home'
import { type SafeToSpendView } from '@/dtos/safe-to-spend'
import { type TransferKind } from '@/ports/records'
import { loadAutoDebit } from '@/use-cases/auto-debit'
import { type BudgetDeps, makeBudgets } from '@/use-cases/budgets'
import { cardBillsOf } from '@/use-cases/card-cycle'
import { type Deps } from '@/use-cases/deps'
import { FUNDING_ITEMS_COLLECTION } from '@/use-cases/funding-plan'
import {
  allPages,
  monthOf,
  requireEntity,
  startOfDay,
  today,
} from '@/use-cases/shared'

type SafeToSpendDeps = BudgetDeps &
  Pick<Deps, 'transfers' | 'bills' | 'documents' | 'recurrences' | 'cardBills'>

// Three months show a monthly income or charge at least twice.
const HISTORY_DAYS = 100
// An unpaid bill older than this was paid outside the app or debited already.
const OVERDUE_DAYS = 20
// A card bill paid early leaves a payment of its amount within this window.
const EARLY_PAYMENT_DAYS = 40
// A card bill also captured as a boleto falls due within days of the card's.
const SAME_BILL_DAYS = 3

const isCash = (account: Account) =>
  CASH_ACCOUNT_TYPES.includes(account.type) &&
  account.balance.currency === 'BRL'

const sum = (amounts: readonly Money[]) =>
  amounts.reduce((total, amount) => total.add(amount), Money.zero())

type Context = {
  day: LocalDate
  until: LocalDate
  entity: FinancialEntity
  recent: readonly Transaction[]
  open: readonly Bill[]
}

// A transfer from the company keeps its kind, so pro-labore and profit
// distribution are two streams even from the same account.
function incomeKey(
  transaction: Transaction,
  kinds: ReadonlyMap<string, TransferKind>,
): string {
  if (transaction.transferGroupId !== null) {
    return `transfer:${kinds.get(transaction.transferGroupId) ?? 'OTHER'}`
  }
  return transaction.counterparty ?? recurrenceKey(transaction)
}

function billObligations(
  bills: readonly Bill[],
  isAutoDebit: (bill: Bill) => boolean,
): Obligation[] {
  return bills.map(bill => ({
    kind: 'BILL',
    label: bill.payee ?? '',
    amount: bill.amount,
    on: bill.dueDate,
    fromReserve: !isAutoDebit(bill),
  }))
}

function fixedObligations(
  items: readonly FundingItemView[],
  context: Context,
): Obligation[] {
  return items.flatMap(item =>
    monthlyDatesBetween(item.dayOfMonth, context.day, context.until).map(
      on => ({
        kind: 'FIXED' as const,
        label: item.name,
        amount: Money.of(item.amount.cents),
        on,
        fromReserve: true,
      }),
    ),
  )
}

export function makeSafeToSpend(deps: SafeToSpendDeps) {
  const budgets = makeBudgets(deps)

  // The Asaas balance pays the fixed items of the person only.
  async function fixedItems(
    kind: EntityKind,
    tenantId: string,
  ): Promise<readonly FundingItemView[]> {
    if (kind !== 'PF') {
      return []
    }
    return deps.documents.list<FundingItemView>(
      tenantId,
      FUNDING_ITEMS_COLLECTION,
    )
  }

  async function budgetsLeft(
    tenantId: string,
    kind: EntityKind,
    day: LocalDate,
  ): Promise<BudgetLeft[]> {
    const month = await budgets.monthView(tenantId, kind, monthOf(day))
    return month.items.map(item => ({
      label: item.name,
      left: Money.of(item.remaining.cents),
    }))
  }

  async function incomeOf(
    tenantId: string,
    entity: FinancialEntity,
    recent: readonly Transaction[],
    day: LocalDate,
  ) {
    const transfers = await deps.transfers.list(tenantId, {
      from: startOfDay(addDays(day, -HISTORY_DAYS)),
      to: startOfDay(addDays(day, 1)),
    })
    const kinds = new Map(
      transfers.map(transfer => [transfer.id, transfer.kind]),
    )
    return expectedIncome(
      recent
        .filter(
          tx =>
            tx.amount.isPositive() && tx.counterparty !== entity.taxId.value,
        )
        .map(tx => ({
          key: incomeKey(tx, kinds),
          on: tx.bookedOn,
          amount: tx.amount,
        })),
      day,
    )
  }

  // Confirmed recurrences charged to a checking account; one charged to a
  // card is already in that card's bill.
  async function subscriptionObligations(
    tenantId: string,
    context: Context,
  ): Promise<Obligation[]> {
    const charged = new Map<string, LocalDate>()
    for (const tx of context.recent.filter(tx => tx.amount.isNegative())) {
      const key = recurrenceKey(tx)
      const known = charged.get(key) ?? ''
      charged.set(key, tx.bookedOn > known ? tx.bookedOn : known)
    }
    const confirmed = (await deps.recurrences.list(tenantId)).filter(
      recurrence =>
        recurrence.entityId === context.entity.id &&
        recurrence.status === 'CONFIRMED' &&
        charged.has(recurrence.key),
    )
    return confirmed.flatMap(recurrence => {
      const lastMonth = monthOf(charged.get(recurrence.key) as LocalDate)
      return monthlyDatesBetween(
        recurrence.dayOfMonth,
        context.day,
        context.until,
      )
        .filter(on => monthOf(on) !== lastMonth)
        .map(on => ({
          kind: 'SUBSCRIPTION' as const,
          label: recurrence.name,
          amount: recurrence.amount,
          on,
          fromReserve: false,
        }))
    })
  }

  async function cardObligations(
    tenantId: string,
    cards: readonly Account[],
    context: Context,
  ): Promise<Obligation[]> {
    const stored = await deps.cardBills.list(
      tenantId,
      cards.map(card => card.id),
    )
    const payments = context.recent.filter(
      tx => tx.amount.isNegative() && isCardBillPayment(tx.description),
    )
    const captured = (cents: number, dueOn: LocalDate) =>
      context.open.some(
        bill =>
          bill.amount.cents === cents &&
          Math.abs(daysBetween(bill.dueDate, dueOn)) <= SAME_BILL_DAYS,
      )
    const paid = (cents: number, dueOn: LocalDate) =>
      payments.some(
        tx =>
          tx.amount.cents === -cents &&
          tx.bookedOn >= addDays(dueOn, -EARLY_PAYMENT_DAYS),
      )
    return cards.flatMap(card =>
      cardBillsOf(
        card,
        stored.filter(bill => bill.accountId === card.id),
        context.day,
      )
        .filter(
          bill =>
            bill.state !== 'PAST' &&
            bill.dueOn <= context.until &&
            bill.total.cents > 0 &&
            !captured(bill.total.cents, bill.dueOn) &&
            !paid(bill.total.cents, bill.dueOn),
        )
        .map(bill => ({
          kind: 'CARD' as const,
          label: card.name,
          amount: Money.of(bill.total.cents),
          on: bill.dueOn,
          fromReserve: false,
        })),
    )
  }

  // How much the entity can spend each day until the next income without
  // touching what bills, fixed payments, subscriptions, cards and the
  // month's budgets will take.
  return async function safeToSpendToday(
    tenantId: string,
    kind: EntityKind = 'PF',
  ): Promise<SafeToSpendView> {
    const day = today(deps.clock.now())
    const entity = await requireEntity(deps.entities, tenantId, kind)
    const accounts = await deps.accounts.listByEntity(tenantId, entity.id)
    const cash = accounts.filter(isCash)
    const spending = cash.filter(account => !account.isReserve)
    const checking = sum(spending.map(account => account.balance))
    const reserve = sum(
      cash.filter(account => account.isReserve).map(account => account.balance),
    )
    const recent = (
      await deps.transactions.all(tenantId, {
        accountIds: spending.map(account => account.id),
        from: addDays(day, -HISTORY_DAYS),
        to: day,
      })
    ).filter(tx => !tx.provisional)
    const income = await incomeOf(tenantId, entity, recent, day)
    const { until } = spendingWindow(day, income)
    const isAutoDebit = await loadAutoDebit(deps, tenantId)
    const open = (
      await allPages(page =>
        deps.bills.list(tenantId, { entityId: entity.id }, page),
      )
    ).filter(
      bill => !isSettled(bill) && bill.dueDate >= addDays(day, -OVERDUE_DAYS),
    )
    const context: Context = { day, until, entity, recent, open }
    const items = await fixedItems(kind, tenantId)
    const result = safeToSpend({
      today: day,
      cash: checking,
      reserve,
      income,
      obligations: [
        ...billObligations(open, isAutoDebit),
        ...fixedObligations(items, context),
        ...(await subscriptionObligations(tenantId, context)),
        ...(await cardObligations(
          tenantId,
          accounts.filter(account => account.type === 'CREDIT_CARD'),
          context,
        )),
      ],
      budgets: await budgetsLeft(tenantId, kind, day),
    })
    return {
      asOf: day,
      entity: kind,
      cash: money(checking),
      reserve: money(reserve),
      total: money(result.total),
      daily: money(result.daily),
      days: result.days,
      until: result.until,
      income: result.income && {
        on: result.income.on,
        amount: money(result.income.amount),
      },
      shortBy: money(result.shortBy),
      lines: result.lines.map(line => ({
        kind: line.kind,
        label: line.label,
        amount: money(line.amount),
        on: line.on,
      })),
    }
  }
}
