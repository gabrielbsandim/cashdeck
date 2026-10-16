import {
  type Account,
  addDays,
  type Bill,
  type BillStatus,
  CASH_ACCOUNT_TYPES,
  type FinancialEntity,
  groupByRecurrence,
  isCardBillPayment,
  normalizeDescription,
  type LocalDate,
  Money,
  recipientKeys,
  shiftMonth,
  summarizeCharges,
  toCounterparty,
  type Transaction,
  ValidationError,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type FundingDebitView,
  type FundingItemInput,
  type FundingItemView,
  type FundingLineView,
  type FundingPlan,
} from '@/dtos/home'
import { NotFoundError } from '@/errors/errors'
import { type AutoDebitCheck, loadAutoDebit } from '@/use-cases/auto-debit'
import { dueAfter, sameDayIn } from '@/use-cases/card-cycle'
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
export const FUNDING_SETTINGS_COLLECTION = 'funding-settings'
const DEBIT_ACCOUNT_ID = 'debit-account'
// Two months tell a monthly debit from a one-off.
const MIN_DEBIT_MONTHS = 2
// An unpaid bill on automatic debit older than this was debited already.
const ARRIVED_DAYS = 20

type DebitSetting = { accountId: string }
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

// Each payee bills again on the same day of the month after its latest bill,
// so the months ahead are known before their bills arrive.
function monthlyDates(
  latest: LocalDate,
  day: LocalDate,
  end: LocalDate,
): LocalDate[] {
  const dates: LocalDate[] = []
  const dayOfMonth = latest.slice(8)
  for (
    let month = shiftMonth(monthOf(latest), 1);
    sameDayIn(month, dayOfMonth) <= end;
    month = shiftMonth(month, 1)
  ) {
    dates.push(sameDayIn(month, dayOfMonth))
  }
  return dates.filter(on => on >= day)
}

const line = (
  name: string,
  amount: Money,
  on: LocalDate,
  kind: FundingLineView['kind'],
): FundingLineView => ({ name, amount: money(amount), on, kind })

function billLines(
  bills: readonly Bill[],
  day: LocalDate,
  end: LocalDate,
): FundingLineView[] {
  const byPayee = new Map<string, Bill[]>()
  for (const bill of bills) {
    byPayee.set(keyOf(bill), [...(byPayee.get(keyOf(bill)) ?? []), bill])
  }
  return [...byPayee.values()].flatMap(own => {
    const latest = [...own].sort((a, b) =>
      b.dueDate.localeCompare(a.dueDate),
    )[0] as Bill
    const name = latest.payee ?? latest.kind
    const arrived = own
      .filter(
        bill =>
          FUNDED.includes(bill.status) &&
          bill.dueDate >= day &&
          bill.dueDate <= end,
      )
      .map(bill => line(name, bill.amount, bill.dueDate, 'BILL'))
    const current = latest.dueDate >= addDays(day, -STALE_DAYS)
    const coming = current
      ? monthlyDates(latest.dueDate, day, end).map(on =>
          line(name, latest.amount, on, 'EXPECTED'),
        )
      : []
    return [...arrived, ...coming]
  })
}

function itemLines(
  items: readonly FundingItemView[],
  day: LocalDate,
  end: LocalDate,
): FundingLineView[] {
  const before = `${shiftMonth(monthOf(day), -1)}-`
  return items.flatMap(item =>
    monthlyDates(
      `${before}${String(item.dayOfMonth).padStart(2, '0')}`,
      day,
      end,
    ).map(on => line(item.name, Money.of(item.amount.cents), on, 'FIXED')),
  )
}

// Loose Pix have no date, so each 30 days sets a month's worth aside upfront.
function pixLines(reserve: Money, day: LocalDate, days: number) {
  if (!reserve.isPositive()) {
    return []
  }
  const starts = Array.from(
    { length: Math.ceil(days / UPCOMING_DAYS) },
    (_, index) => addDays(day, index * UPCOMING_DAYS),
  )
  return starts.map(on => line('', reserve, on, 'PIX'))
}

type Commitments = {
  isAutoDebit: AutoDebitCheck
  bills: Bill[]
  items: FundingItemView[]
  pixReserve: Money
}

function linesAhead(
  commitments: Commitments,
  day: LocalDate,
  days: number,
): FundingLineView[] {
  const end = addDays(day, days)
  const bills = commitments.bills.filter(bill => !commitments.isAutoDebit(bill))
  return [
    ...billLines(bills, day, end),
    ...itemLines(commitments.items, day, end),
    ...pixLines(commitments.pixReserve, day, days),
  ].sort((a, b) => a.on.localeCompare(b.on))
}

// What the bank debits by itself every month: the mortgage, power and TV
// bills on automatic debit. Each one counts once, at its next date.
function nextDebits(
  sent: readonly Transaction[],
  day: LocalDate,
): FundingDebitView[] {
  const debits = sent.filter(
    tx =>
      tx.transferGroupId === null &&
      toCounterparty(tx.counterparty)?.length !== 11 &&
      !isCardBillPayment(tx.description),
  )
  return [...groupByRecurrence(debits)]
    .map(([key, group]) => summarizeCharges(key, group))
    .filter(
      charge =>
        charge.months >= MIN_DEBIT_MONTHS &&
        charge.charges.length <= charge.months + 1 &&
        charge.lastChargeOn >= addDays(day, -STALE_DAYS),
    )
    .map(charge => ({
      name: charge.name,
      amount: money(charge.amount),
      on: dueAfter(charge.lastChargeOn, day),
    }))
    .sort((a, b) => a.on.localeCompare(b.on))
}

const wordsOf = (text: string) =>
  new Set(
    normalizeDescription(text)
      .split(' ')
      .filter(word => word !== ''),
  )

const names = (bill: Bill, debit: FundingDebitView) => {
  const words = wordsOf(debit.name)
  return [...wordsOf(bill.payee ?? '')].some(word => words.has(word))
}

// A metered bill changes every month, so one that already arrived says what
// the bank takes better than last month's debit does.
function withArrived(
  debits: readonly FundingDebitView[],
  arrived: readonly Bill[],
): FundingDebitView[] {
  const used = new Set<string>()
  const known = debits.map(debit => {
    const bill = arrived.find(
      other => !used.has(other.id) && names(other, debit),
    )
    if (!bill) {
      return debit
    }
    used.add(bill.id)
    return { ...debit, amount: money(bill.amount) }
  })
  const fresh = arrived
    .filter(bill => !used.has(bill.id))
    .map(bill => ({
      name: bill.payee ?? bill.kind,
      amount: money(bill.amount),
      on: bill.dueDate,
    }))
  return [...known, ...fresh].sort((a, b) => a.on.localeCompare(b.on))
}

type DebitHistory = { account: Account; sent: Transaction[] }

async function debitHistory(
  deps: Pick<Deps, 'accounts' | 'transactions' | 'documents'>,
  tenantId: string,
  day: LocalDate,
): Promise<DebitHistory | null> {
  const setting = await deps.documents.get<DebitSetting>(
    tenantId,
    FUNDING_SETTINGS_COLLECTION,
    DEBIT_ACCOUNT_ID,
  )
  const account = setting
    ? await deps.accounts.findById(tenantId, setting.accountId)
    : null
  if (!account) {
    return null
  }
  const sent = await deps.transactions.all(tenantId, {
    accountIds: [account.id],
    from: `${addMonths(monthOf(day), -HISTORY_MONTHS)}-01`,
    to: day,
  })
  return { account, sent }
}

function debitPlan(
  history: DebitHistory | null,
  day: LocalDate,
  arrived: readonly Bill[],
): FundingPlan['debit'] {
  if (!history) {
    return null
  }
  const { account, sent } = history
  const items = withArrived(nextDebits(sent, day), arrived)
  const total = sum(items.map(item => Money.of(item.amount.cents)))
  const shortfall = total.subtract(account.balance)
  return {
    accountId: account.id,
    name: account.name,
    balance: money(account.balance),
    items,
    total: money(total),
    topUp: money(shortfall.isPositive() ? shortfall : Money.zero()),
  }
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

type CommitmentDeps = Pick<
  Deps,
  'bills' | 'documents' | 'accounts' | 'transactions'
>

async function loadCommitments(
  deps: CommitmentDeps,
  tenantId: string,
  entity: FinancialEntity,
  day: LocalDate,
): Promise<Commitments> {
  const [isAutoDebit, stored, items, pixReserve] = await Promise.all([
    loadAutoDebit(deps, tenantId),
    allPages(request =>
      deps.bills.list(tenantId, { entityId: entity.id }, request),
    ),
    listItems(deps, tenantId),
    loosePixReserve(deps, tenantId, entity, day),
  ])
  const bills = stored.filter(bill => bill.status !== 'CANCELLED')
  return { isAutoDebit, bills, items, pixReserve }
}

// What the reserve pays over the next days, dated, so the home can tell how
// long its balance lasts with the same numbers the funding plan uses.
export async function commitmentsAhead(
  deps: CommitmentDeps,
  tenantId: string,
  entity: FinancialEntity,
  day: LocalDate,
  days: number,
): Promise<FundingLineView[]> {
  return linesAhead(
    await loadCommitments(deps, tenantId, entity, day),
    day,
    days,
  )
}

// What the Asaas balance pays in the next 30 days and what to send so it can.
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
    const [commitments, balance, history] = await Promise.all([
      loadCommitments(deps, tenantId, entity, day),
      balanceOf(tenantId, entity.id),
      debitHistory(deps, tenantId, day),
    ])
    const lines = linesAhead(commitments, day, UPCOMING_DAYS)
    const needed = sum(lines.map(item => Money.of(item.amount.cents)))
    const shortfall = needed.subtract(balance ?? Money.zero())
    const end = addDays(day, UPCOMING_DAYS)
    return {
      balance: balance && money(balance),
      needed: money(needed),
      topUp: money(shortfall.isPositive() ? shortfall : Money.zero()),
      lines,
      items: commitments.items,
      debit: debitPlan(
        history,
        day,
        commitments.bills.filter(
          bill =>
            commitments.isAutoDebit(bill) &&
            FUNDED.includes(bill.status) &&
            bill.dueDate >= addDays(day, -ARRIVED_DAYS) &&
            bill.dueDate <= end,
        ),
      ),
    }
  }
}

// The account the bank debits by itself; the plan says what it needs too.
export function makeSetDebitAccount(
  deps: Pick<Deps, 'accounts' | 'documents' | 'entities'>,
) {
  return async function setDebitAccount(
    tenantId: string,
    accountId: string | null,
  ): Promise<{ accountId: string | null }> {
    if (accountId === null) {
      await deps.documents.delete(
        tenantId,
        FUNDING_SETTINGS_COLLECTION,
        DEBIT_ACCOUNT_ID,
      )
      return { accountId }
    }
    const entity = await requireEntity(deps.entities, tenantId, 'PF')
    const account = await deps.accounts.findById(tenantId, accountId)
    if (!account) {
      throw new NotFoundError('Account')
    }
    const usable =
      account.entityId === entity.id &&
      CASH_ACCOUNT_TYPES.includes(account.type)
    if (!usable) {
      throw new ValidationError('Pick a personal checking or savings account.')
    }
    await deps.documents.put<DebitSetting>(
      tenantId,
      FUNDING_SETTINGS_COLLECTION,
      DEBIT_ACCOUNT_ID,
      { accountId },
    )
    return { accountId }
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
