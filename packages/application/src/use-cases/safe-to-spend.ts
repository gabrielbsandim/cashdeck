import {
  type Account,
  addDays,
  type Bill,
  CASH_ACCOUNT_TYPES,
  type BudgetLeft,
  cashShortfall,
  chargesInstallment,
  debitOn,
  daysBetween,
  type EntityKind,
  expectedIncome,
  type FinancialEntity,
  installmentIn,
  isSettled,
  type LocalDate,
  Money,
  type MonthFlow,
  monthlyAllowance,
  monthlyDatesBetween,
  type Obligation,
  recurrenceKey,
  type SafeToSpendLine,
  safeToSpend,
  spendingWindow,
  type Transaction,
  type TypicalMonth,
  typicalMonth,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type FundingItemView } from '@/dtos/home'
import { type SafeToSpendView } from '@/dtos/safe-to-spend'
import { type Recurrence, type TransferKind } from '@/ports/records'
import { loadAutoDebit } from '@/use-cases/auto-debit'
import { type BudgetDeps, makeBudgets } from '@/use-cases/budgets'
import { cardBillsOf } from '@/use-cases/card-cycle'
import { type Deps } from '@/use-cases/deps'
import { FUNDING_ITEMS_COLLECTION } from '@/use-cases/funding-plan'
import {
  categoryIndex,
  type FlowEntry,
  flowEntries,
  insightScope,
} from '@/use-cases/insights'
import { loadLoans, type StoredLoan } from '@/use-cases/loans'
import { incomeTest, loadSpendingPlan } from '@/use-cases/spending-plan'
import {
  addMonths,
  allPages,
  firstDay,
  lastDay,
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
// A card bill paid early leaves a debit of its exact amount within this
// window; banks describe it as a plain boleto as often as a card payment.
const EARLY_PAYMENT_DAYS = 40
// A card bill also captured as a boleto falls due within days of the card's.
const SAME_BILL_DAYS = 3
// Closed months the typical income and spending are read from; few, since an
// hourly rate that rises shows in the income within a quarter.
const PLAN_MONTHS = 3
// Income days are irregular, so the cash check looks a month ahead instead.
const CASH_ALERT_DAYS = 30

const isCash = (account: Account) =>
  CASH_ACCOUNT_TYPES.includes(account.type) &&
  account.balance.currency === 'BRL'

const sum = (amounts: readonly Money[]) =>
  amounts.reduce((total, amount) => total.add(amount), Money.zero())

// Words every biller uses, so sharing one says nothing about the payee.
const GENERIC_WORDS = new Set(['FATURA', 'CONTA', 'BOLETO', 'LTDA', 'EIRELI'])

const nameWords = (name: string) =>
  name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toUpperCase()
    .split(/[^A-Z0-9]+/)
    .filter(word => word.length >= 4 && !GENERIC_WORDS.has(word))

const sharesWord = (a: string, b: string) =>
  nameWords(a).some(word => nameWords(b).includes(word))

type Context = {
  day: LocalDate
  until: LocalDate
  entity: FinancialEntity
  recent: readonly Transaction[]
  open: readonly Bill[]
  loans: readonly StoredLoan[]
}

type Base = Omit<Context, 'until'> & {
  tenantId: string
  kind: EntityKind
  accounts: readonly Account[]
  checking: Money
  reserve: Money
  isAutoDebit: (bill: Bill) => boolean
  items: readonly FundingItemView[]
}

// Which recurring charges count and since when their last charge must be.
type RecurringScope = {
  charges: readonly Transaction[]
  include: (recurrence: Recurrence) => boolean
  since: string
}

type Plan = {
  typical: TypicalMonth
  received: Money
  sources: number
  savings: Money
  savingsSet: boolean
  entries: readonly FlowEntry[]
  cards: ReadonlySet<string>
}

const lineView = (line: SafeToSpendLine) => ({
  kind: line.kind,
  label: line.label,
  amount: money(line.amount),
  on: line.on,
})

const isCard = (account: Account) => account.type === 'CREDIT_CARD'

const centsOf = (entries: readonly FlowEntry[]) =>
  entries.reduce((total, entry) => total + entry.cents, 0)

function closedMonths(
  entries: readonly FlowEntry[],
  month: string,
  isIncome: (entry: FlowEntry) => boolean,
): MonthFlow[] {
  const months = Array.from({ length: PLAN_MONTHS }, (_, index) =>
    addMonths(month, index - PLAN_MONTHS),
  )
  return months.flatMap(closed => {
    const inMonth = entries.filter(
      entry => monthOf(entry.transaction.bookedOn) === closed,
    )
    if (inMonth.length === 0) {
      return []
    }
    return [
      {
        month: closed,
        income: centsOf(inMonth.filter(isIncome)),
        expenses: centsOf(inMonth.filter(entry => entry.kind === 'EXPENSE')),
      },
    ]
  })
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

// The month's installment of the schedule, not the last debit, which may carry
// a late fee; nothing once the loan is paid off. One past due keeps the
// debit's usual day.
function loanObligations(
  loan: StoredLoan,
  on: LocalDate,
  day: LocalDate,
): Obligation[] {
  const due = installmentIn(loan, monthOf(on))
  if (!due) {
    return []
  }
  const debit = debitOn(due)
  return [
    {
      kind: 'LOAN',
      label: `${loan.lender} ${loan.contract}`,
      amount: Money.of(due.total),
      on: debit >= day ? debit : on,
      fromReserve: false,
    },
  ]
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

  // Recurring charges still to come by the window end; one charged this month
  // already, or captured as a bill of that month, is not owed again.
  async function recurringObligations(
    tenantId: string,
    context: Context,
    scope: RecurringScope,
  ): Promise<Obligation[]> {
    const charged = new Map<string, LocalDate>()
    for (const tx of scope.charges.filter(tx => tx.amount.isNegative())) {
      const key = recurrenceKey(tx)
      const known = charged.get(key) ?? ''
      charged.set(key, tx.bookedOn > known ? tx.bookedOn : known)
    }
    const lastMonthOf = (recurrence: Recurrence) =>
      monthOf(charged.get(recurrence.key) as LocalDate)
    const running = (await deps.recurrences.list(tenantId)).filter(
      recurrence =>
        recurrence.entityId === context.entity.id &&
        scope.include(recurrence) &&
        charged.has(recurrence.key) &&
        lastMonthOf(recurrence) >= scope.since,
    )
    const billed = (name: string, on: LocalDate) =>
      context.open.some(
        bill =>
          monthOf(bill.dueDate) === monthOf(on) &&
          sharesWord(bill.payee ?? '', name),
      )
    const loanOf = (recurrence: Recurrence) =>
      context.loans.find(loan =>
        chargesInstallment(loan, recurrence.amount.cents),
      )
    return running.flatMap(recurrence => {
      const lastMonth = lastMonthOf(recurrence)
      const loan = loanOf(recurrence)
      return monthlyDatesBetween(
        recurrence.dayOfMonth,
        context.day,
        context.until,
      )
        .filter(on => monthOf(on) !== lastMonth && !billed(recurrence.name, on))
        .flatMap((on): Obligation[] => {
          if (loan) {
            return loanObligations(loan, on, context.day)
          }
          return [
            {
              kind:
                recurrence.status === 'CONFIRMED' ? 'SUBSCRIPTION' : 'FIXED',
              label: recurrence.name,
              amount: recurrence.amount,
              on,
              fromReserve: false,
            },
          ]
        })
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
    const payments = context.recent.filter(tx => tx.amount.isNegative())
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

  async function load(tenantId: string, kind: EntityKind): Promise<Base> {
    const day = today(deps.clock.now())
    const entity = await requireEntity(deps.entities, tenantId, kind)
    const accounts = await deps.accounts.listByEntity(tenantId, entity.id)
    const cash = accounts.filter(isCash)
    const spending = cash.filter(account => !account.isReserve)
    const recent = (
      await deps.transactions.all(tenantId, {
        accountIds: spending.map(account => account.id),
        from: addDays(day, -HISTORY_DAYS),
        to: day,
      })
    ).filter(tx => !tx.provisional)
    const open = (
      await allPages(page =>
        deps.bills.list(tenantId, { entityId: entity.id }, page),
      )
    ).filter(
      bill => !isSettled(bill) && bill.dueDate >= addDays(day, -OVERDUE_DAYS),
    )
    return {
      tenantId,
      kind,
      day,
      entity,
      accounts,
      recent,
      open,
      checking: sum(spending.map(account => account.balance)),
      reserve: sum(
        cash
          .filter(account => account.isReserve)
          .map(account => account.balance),
      ),
      isAutoDebit: await loadAutoDebit(deps, tenantId),
      items: await fixedItems(kind, tenantId),
      loans: (await loadLoans(deps, tenantId)).filter(
        loan => loan.entityId === entity.id,
      ),
    }
  }

  // Everything due by `until` that leaves the checking accounts, card bills
  // included, as the cash itself has to pay it.
  async function cashObligations(
    base: Base,
    until: LocalDate,
    recurring: Omit<RecurringScope, 'charges'>,
  ): Promise<Obligation[]> {
    const context: Context = { ...base, until }
    return [
      ...billObligations(base.open, base.isAutoDebit),
      ...fixedObligations(base.items, context),
      ...(await recurringObligations(base.tenantId, context, {
        charges: base.recent,
        ...recurring,
      })),
      ...(await cardObligations(
        base.tenantId,
        base.accounts.filter(isCard),
        context,
      )),
    ]
  }

  function baseView(base: Base) {
    return {
      asOf: base.day,
      entity: base.kind,
      cash: money(base.checking),
      reserve: money(base.reserve),
    }
  }

  // Until the next income: for a company, or a person without a closed month.
  async function cashView(base: Base): Promise<SafeToSpendView> {
    const income = await incomeOf(
      base.tenantId,
      base.entity,
      base.recent,
      base.day,
    )
    const { until } = spendingWindow(base.day, income)
    const result = safeToSpend({
      today: base.day,
      cash: base.checking,
      reserve: base.reserve,
      income,
      obligations: await cashObligations(base, until, {
        include: recurrence => recurrence.status === 'CONFIRMED',
        since: '',
      }),
      budgets: await budgetsLeft(base.tenantId, base.kind, base.day),
    })
    return {
      ...baseView(base),
      basis: 'CASH',
      total: money(result.total),
      daily: money(result.daily),
      days: result.days,
      until: result.until,
      income: result.income && {
        on: result.income.on,
        amount: money(result.income.amount),
      },
      plan: null,
      shortBy: money(result.shortBy),
      cashShortBy: money(result.shortBy),
      lines: result.lines.map(lineView),
    }
  }

  async function planOf(base: Base): Promise<Plan | null> {
    const scope = await insightScope(deps, base.tenantId, base.kind)
    const month = monthOf(base.day)
    const entries = await flowEntries(
      deps,
      base.tenantId,
      scope.accounts,
      await categoryIndex(deps, base.tenantId),
      { from: firstDay(addMonths(month, -PLAN_MONTHS)), to: base.day },
    )
    const stored = await loadSpendingPlan(deps, base.tenantId, base.entity.id)
    const cards = new Set(
      scope.accounts.filter(isCard).map(account => account.id),
    )
    // An unconfirmed purchase already counts; an unconfirmed credit frees nothing.
    const fromSources = incomeTest(stored.incomeSources, cards)
    const isIncome = (entry: FlowEntry) =>
      !entry.transaction.provisional && fromSources(entry)
    const typical = typicalMonth(closedMonths(entries, month, isIncome))
    if (!typical) {
      return null
    }
    const target = stored.savings
    return {
      typical,
      received: Money.of(
        centsOf(
          entries.filter(
            entry =>
              monthOf(entry.transaction.bookedOn) === month && isIncome(entry),
          ),
        ),
      ),
      sources: stored.incomeSources.length,
      savings: target ? Money.of(target.cents) : typical.saved,
      savingsSet: target !== null,
      entries,
      cards,
    }
  }

  // A captured boleto or a debit of a card bill's exact total pays purchases
  // the month already counted on the card.
  async function cardBillTotals(base: Base) {
    const cards = base.accounts.filter(isCard)
    const stored = await deps.cardBills.list(
      base.tenantId,
      cards.map(card => card.id),
    )
    const dues = cards.flatMap(card =>
      cardBillsOf(
        card,
        stored.filter(bill => bill.accountId === card.id),
        base.day,
      ),
    )
    const matches = (cents: number, on: LocalDate, days: number) =>
      dues.some(
        due =>
          due.total.cents === cents &&
          Math.abs(daysBetween(due.dueOn, on)) <= days,
      )
    return {
      boleto: (bill: Bill) =>
        matches(bill.amount.cents, bill.dueDate, SAME_BILL_DAYS),
      payment: (tx: Transaction) =>
        matches(-tx.amount.cents, tx.bookedOn, EARLY_PAYMENT_DAYS),
    }
  }

  // What the typical month leaves after the savings target, less what this
  // month already spent on cards and accounts and what it still owes.
  async function monthView(base: Base, plan: Plan): Promise<SafeToSpendView> {
    const month = monthOf(base.day)
    const context: Context = { ...base, until: lastDay(month) }
    // Any recurring debit still running is owed, a dismissed subscription too.
    const running = { include: () => true, since: addMonths(month, -1) }
    const cardBill = await cardBillTotals(base)
    const spent = plan.entries.filter(
      entry =>
        entry.kind === 'EXPENSE' &&
        monthOf(entry.transaction.bookedOn) === month &&
        !cardBill.payment(entry.transaction),
    )
    const spentOn = (onCard: boolean) =>
      Money.of(
        spent
          .filter(
            entry => plan.cards.has(entry.transaction.accountId) === onCard,
          )
          .reduce((total, entry) => total + entry.cents, 0),
      )
    const income = Money.of(
      Math.max(plan.typical.income.cents, plan.received.cents),
    )
    const result = monthlyAllowance({
      today: base.day,
      income,
      savings: plan.savings,
      spentOnCards: spentOn(true),
      spentFromAccounts: spentOn(false),
      obligations: [
        ...billObligations(
          base.open.filter(bill => !cardBill.boleto(bill)),
          base.isAutoDebit,
        ),
        ...fixedObligations(base.items, context),
        ...(await recurringObligations(base.tenantId, context, {
          charges: plan.entries
            .filter(entry => entry.kind === 'EXPENSE')
            .map(entry => entry.transaction),
          ...running,
        })),
      ],
      budgets: await budgetsLeft(base.tenantId, base.kind, base.day),
    })
    const until = addDays(base.day, CASH_ALERT_DAYS)
    return {
      ...baseView(base),
      basis: 'MONTH',
      total: money(result.total),
      daily: money(result.daily),
      days: result.days,
      until: result.until,
      income: null,
      plan: {
        income: money(income),
        typical: money(plan.typical.income),
        received: money(plan.received),
        savings: money(plan.savings),
        savingsSet: plan.savingsSet,
        months: plan.typical.months,
        sources: plan.sources,
      },
      shortBy: money(result.shortBy),
      cashShortBy: money(
        cashShortfall({
          until,
          cash: base.checking,
          reserve: base.reserve,
          obligations: await cashObligations(base, until, running),
        }),
      ),
      lines: result.lines.map(lineView),
    }
  }

  // A person's free money follows a monthly plan, since income days and
  // amounts vary and most spending goes on cards; a company's runs on cash.
  async function safeToSpendToday(
    tenantId: string,
    kind: EntityKind = 'PF',
  ): Promise<SafeToSpendView> {
    const base = await load(tenantId, kind)
    const plan = kind === 'PF' ? await planOf(base) : null
    if (!plan) {
      return cashView(base)
    }
    return monthView(base, plan)
  }

  return safeToSpendToday
}
