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
import { householdTaxIds } from '@/use-cases/household'
import { FUNDING_ITEMS_COLLECTION } from '@/use-cases/funding-plan'
import {
  categoryIndex,
  type FlowEntry,
  flowEntries,
  flowKeyOf,
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
  paidToday: readonly Bill[]
}

type Owner = Pick<Base, 'tenantId' | 'kind' | 'entity' | 'day'>

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
  invested: Money
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

const EARLY_DAYS = 5

// A payer who pays a month a few days early, as a tenant paying on the 31st,
// leaves that month empty; the credit counts there, never past this month.
function incomeMonthOf(
  incomes: readonly FlowEntry[],
  month: string,
): (entry: FlowEntry) => string {
  const payerOf = (entry: FlowEntry) => entry.transaction.counterparty ?? ''
  const paid = new Set(
    incomes.map(
      entry => `${payerOf(entry)}|${monthOf(entry.transaction.bookedOn)}`,
    ),
  )
  return entry => {
    const booked = monthOf(entry.transaction.bookedOn)
    const next = addMonths(booked, 1)
    const early =
      daysBetween(entry.transaction.bookedOn, lastDay(booked)) < EARLY_DAYS
    return early && next <= month && !paid.has(`${payerOf(entry)}|${next}`)
      ? next
      : booked
  }
}

function closedMonths(
  entries: readonly FlowEntry[],
  month: string,
  isIncome: (entry: FlowEntry) => boolean,
): MonthFlow[] {
  const incomes = entries.filter(isIncome)
  const incomeMonth = incomeMonthOf(incomes, month)
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
        income: centsOf(incomes.filter(entry => incomeMonth(entry) === closed)),
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
    const [transfers, members] = await Promise.all([
      deps.transfers.list(tenantId, {
        from: startOfDay(addDays(day, -HISTORY_DAYS)),
        to: startOfDay(addDays(day, 1)),
      }),
      entity.kind === 'PF' ? householdTaxIds(deps, tenantId) : [],
    ])
    const kinds = new Map(
      transfers.map(transfer => [transfer.id, transfer.kind]),
    )
    const own = new Set([entity.taxId.value, ...members])
    return expectedIncome(
      recent
        .filter(tx => tx.amount.isPositive() && !own.has(tx.counterparty ?? ''))
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
      // One whose day passed this month without the debit is late, still owed.
      return monthlyDatesBetween(
        recurrence.dayOfMonth,
        firstDay(monthOf(context.day)),
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

  async function load(owner: Owner): Promise<Base> {
    const { tenantId, kind, entity, day } = owner
    const [accounts, bills, isAutoDebit, items, loans] = await Promise.all([
      deps.accounts.listByEntity(tenantId, entity.id),
      allPages(page =>
        deps.bills.list(tenantId, { entityId: entity.id }, page),
      ),
      loadAutoDebit(deps, tenantId),
      fixedItems(kind, tenantId),
      loadLoans(deps, tenantId),
    ])
    const cash = accounts.filter(isCash)
    const spending = cash.filter(account => !account.isReserve)
    const recent = (
      await deps.transactions.all(tenantId, {
        accountIds: spending.map(account => account.id),
        from: addDays(day, -HISTORY_DAYS),
        to: day,
      })
    ).filter(tx => !tx.provisional)
    return {
      tenantId,
      kind,
      day,
      entity,
      accounts,
      recent,
      open: bills.filter(
        bill => !isSettled(bill) && bill.dueDate >= addDays(day, -OVERDUE_DAYS),
      ),
      paidToday: bills.filter(
        bill => isSettled(bill) && bill.paidAt && today(bill.paidAt) === day,
      ),
      checking: sum(spending.map(account => account.balance)),
      reserve: sum(
        cash
          .filter(account => account.isReserve)
          .map(account => account.balance),
      ),
      isAutoDebit,
      items,
      loans: loans.filter(loan => loan.entityId === entity.id),
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
    const [recurrent, cards] = await Promise.all([
      recurringObligations(base.tenantId, context, {
        charges: base.recent,
        ...recurring,
      }),
      cardObligations(base.tenantId, base.accounts.filter(isCard), context),
    ])
    return [
      ...billObligations(base.open, base.isAutoDebit),
      ...fixedObligations(base.items, context),
      ...recurrent,
      ...cards,
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

  // A bill or a recurring charge paid today was owed this morning already.
  async function dueSettlement(base: Base) {
    const keys = new Set(
      (await deps.recurrences.list(base.tenantId))
        .filter(recurrence => recurrence.entityId === base.entity.id)
        .map(recurrence => recurrence.key),
    )
    return (tx: Transaction) =>
      keys.has(recurrenceKey(tx)) ||
      base.paidToday.some(bill => bill.amount.cents === -tx.amount.cents)
  }

  // Until the next income: for a company, or a person without a closed month.
  async function cashView(base: Base): Promise<SafeToSpendView> {
    const [income, budgets, settlesDue] = await Promise.all([
      incomeOf(base.tenantId, base.entity, base.recent, base.day),
      budgetsLeft(base.tenantId, base.kind, base.day),
      dueSettlement(base),
    ])
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
      budgets,
      spentToday: sum(
        base.recent
          .filter(
            tx =>
              tx.bookedOn === base.day &&
              tx.amount.isNegative() &&
              !settlesDue(tx),
          )
          .map(tx => tx.amount),
      ).negate(),
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

  // Money moved into an investment account was put away before any product
  // shows it; what the account then buys inside it moves nothing.
  async function movedToInvestments(
    owner: Owner,
    accounts: readonly Account[],
    categories: Awaited<ReturnType<typeof categoryIndex>>,
  ) {
    const moved = await deps.transactions.all(owner.tenantId, {
      accountIds: accounts
        .filter(account => account.type === 'INVESTMENT')
        .map(account => account.id),
      from: firstDay(monthOf(owner.day)),
      to: owner.day,
    })
    return moved
      .filter(tx => flowKeyOf(categories, tx.categoryId) === 'transfers')
      .reduce((total, tx) => total + tx.amount.cents, 0)
  }

  async function planOf(owner: Owner): Promise<Plan | null> {
    const month = monthOf(owner.day)
    const [scope, categories, stored, holdings] = await Promise.all([
      insightScope(deps, owner.tenantId, owner.kind),
      categoryIndex(deps, owner.tenantId),
      loadSpendingPlan(deps, owner.tenantId, owner.entity.id),
      deps.accounts.listByEntity(owner.tenantId, owner.entity.id),
    ])
    const entries = await flowEntries(
      deps,
      owner.tenantId,
      scope.accounts,
      categories,
      { from: firstDay(addMonths(month, -PLAN_MONTHS)), to: owner.day },
    )
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
    const incomes = entries.filter(isIncome)
    const incomeMonth = incomeMonthOf(incomes, month)
    return {
      typical,
      received: Money.of(
        centsOf(incomes.filter(entry => incomeMonth(entry) === month)),
      ),
      sources: stored.incomeSources.length,
      savings: target ? Money.of(target.cents) : typical.saved,
      savingsSet: target !== null,
      invested: Money.of(
        (await movedToInvestments(owner, holdings, categories)) -
          entries
            .filter(
              entry =>
                monthOf(entry.transaction.bookedOn) === month &&
                flowKeyOf(categories, entry.transaction.categoryId) ===
                  'investments',
            )
            .reduce(
              (total, entry) => total + entry.transaction.amount.cents,
              0,
            ),
      ),
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
    const until = addDays(base.day, CASH_ALERT_DAYS)
    const [cardBill, recurrent, budgets, upcoming, settlesDue] =
      await Promise.all([
        cardBillTotals(base),
        recurringObligations(base.tenantId, context, {
          charges: plan.entries
            .filter(entry => entry.kind === 'EXPENSE')
            .map(entry => entry.transaction),
          ...running,
        }),
        budgetsLeft(base.tenantId, base.kind, base.day),
        cashObligations(base, until, running),
        dueSettlement(base),
      ])
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
      invested: plan.invested,
      spentOnCards: spentOn(true),
      spentFromAccounts: spentOn(false),
      spentToday: Money.of(
        spent
          .filter(
            entry =>
              entry.transaction.bookedOn === base.day &&
              !settlesDue(entry.transaction),
          )
          .reduce((total, entry) => total + entry.cents, 0),
      ),
      obligations: [
        ...billObligations(
          base.open.filter(bill => !cardBill.boleto(bill)),
          base.isAutoDebit,
        ),
        ...fixedObligations(base.items, context),
        ...recurrent,
      ],
      budgets,
    })
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
          obligations: upcoming,
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
    const day = today(deps.clock.now())
    const entity = await requireEntity(deps.entities, tenantId, kind)
    const owner = { tenantId, kind, entity, day }
    const [base, plan] = await Promise.all([
      load(owner),
      kind === 'PF' ? planOf(owner) : null,
    ])
    if (!plan) {
      return cashView(base)
    }
    return monthView(base, plan)
  }

  return safeToSpendToday
}
