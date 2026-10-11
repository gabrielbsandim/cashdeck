import {
  type Account,
  addDays,
  type BillCycle,
  billPayment,
  chargesIn,
  cycleHolds,
  cyclesAfter,
  groupInstallments,
  CASH_ACCOUNT_TYPES,
  type LocalDate,
  Money,
  openBillOf,
  type ProjectedInstallment,
  projectInstallments,
  type Transaction,
  ValidationError,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type CardTimelineView } from '@/dtos/insights'
import { cardBillsOf } from '@/use-cases/card-cycle'
import { type Deps } from '@/use-cases/deps'
import { required, requireEntityById, today } from '@/use-cases/shared'

type TimelineDeps = Pick<
  Deps,
  'entities' | 'accounts' | 'cardBills' | 'transactions' | 'clock'
>

type KnownBill = ReturnType<typeof cardBillsOf>[number]
type TimelineBill = CardTimelineView['bills'][number]

const MONTHS_AHEAD = 12
// Long enough to hold the latest charge of any plan still running and the
// payment of the oldest bill shown.
const HISTORY_DAYS = 400

const cycleOf = (bill: KnownBill): BillCycle => ({
  from: bill.range.from,
  closesOn: bill.range.to,
  dueOn: bill.dueOn,
})

// A bill paid by boleto from a cash account shows on the card only on the
// next statement, so a debit of exactly its total settles it too.
function settledBy(
  total: Money,
  transactions: readonly Transaction[],
  elsewhere: readonly Transaction[],
) {
  const exact = elsewhere
    .filter(transaction => transaction.amount.cents === -total.cents)
    .map(transaction => ({ ...transaction, amount: total }))
  return [...transactions, ...exact]
}

function knownView(
  bill: KnownBill,
  transactions: readonly Transaction[],
  elsewhere: readonly Transaction[],
  day: LocalDate,
): TimelineBill {
  const total = Money.of(bill.total.cents)
  return {
    ...bill,
    payment:
      bill.state === 'OPEN'
        ? null
        : billPayment(
            cycleOf(bill),
            total,
            settledBy(total, transactions, elsewhere),
            day,
          ),
    installments: [],
  }
}

// A cycle the issuer has not billed yet: what is already posted to it plus
// the installments it will carry.
function forecastView(
  cycle: BillCycle,
  installments: readonly ProjectedInstallment[],
  transactions: readonly Transaction[],
  day: LocalDate,
): TimelineBill {
  const projected = installments.reduce(
    (sum, item) => sum + item.amount.cents,
    0,
  )
  return {
    closesOn: cycle.closesOn,
    dueOn: cycle.dueOn,
    total: money(Money.of(chargesIn(cycle, transactions).cents + projected)),
    minimum: null,
    state: cycleHolds(cycle, day) ? 'OPEN' : 'FORECAST',
    payment: null,
    range: { from: cycle.from, to: cycle.closesOn },
    installments: installments.map(item => ({
      ...item,
      amount: money(item.amount),
    })),
  }
}

type Timeline = Pick<CardTimelineView, 'bills' | 'current'>

async function cashActivity(
  deps: TimelineDeps,
  tenantId: string,
  card: Account,
  range: { from: LocalDate; to: LocalDate },
) {
  const cash = (await deps.accounts.list(tenantId)).filter(
    account =>
      account.entityId === card.entityId &&
      CASH_ACCOUNT_TYPES.includes(account.type),
  )
  return cash.length === 0
    ? []
    : deps.transactions.all(tenantId, {
        accountIds: cash.map(account => account.id),
        ...range,
      })
}

async function timelineOf(
  deps: TimelineDeps,
  tenantId: string,
  card: Account,
  day: LocalDate,
): Promise<Timeline> {
  const stored = await deps.cardBills.list(tenantId, [card.id])
  const known = cardBillsOf(card, stored, day).reverse()
  const latest = known.at(-1)
  if (!latest) {
    return { bills: [], current: null }
  }
  const ahead = cyclesAfter(cycleOf(latest), MONTHS_AHEAD)
  const range = {
    from: addDays(day, -HISTORY_DAYS),
    to: (ahead.at(-1) as BillCycle).closesOn,
  }
  const transactions = await deps.transactions.all(tenantId, {
    accountIds: [card.id],
    ...range,
  })
  const elsewhere = await cashActivity(deps, tenantId, card, range)
  const projected = projectInstallments(groupInstallments(transactions), [
    ...known.map(cycleOf),
    ...ahead,
  ])
  const forecasts = ahead
    .map((cycle, index) =>
      forecastView(
        cycle,
        projected[known.length + index] as ProjectedInstallment[],
        transactions,
        day,
      ),
    )
    .filter(bill => bill.range.to >= day)
  const last = forecasts.findLastIndex(
    bill => bill.state === 'OPEN' || bill.total.cents > 0,
  )
  // Without a credit line the open bill has no issuer total, so it is
  // forecast from what is posted, like the cycles after it.
  const bills = [
    ...known.map((bill, index) =>
      bill.state === 'OPEN' && card.credit === null
        ? forecastView(
            cycleOf(bill),
            projected[index] as ProjectedInstallment[],
            transactions,
            day,
          )
        : knownView(bill, transactions, elsewhere, day),
    ),
    ...forecasts.slice(0, last + 1),
  ]
  // The open bill is the latest known one or a cycle after it.
  const open = bills.findIndex(bill => bill.state === 'OPEN')
  return { bills, current: Math.max(open, known.length - 1) }
}

export type CardDue = { total: Money; dueOn: LocalDate | null }

// What the card asks to be paid next: a closed bill still unpaid, else the
// open one. A manual card without dates or balance owes what is posted to it.
async function dueOf(
  deps: TimelineDeps,
  tenantId: string,
  card: Account,
  day: LocalDate,
): Promise<CardDue> {
  const { bills } = await timelineOf(deps, tenantId, card, day)
  const next =
    bills.find(bill => bill.state === 'CLOSED' && bill.payment !== 'PAID') ??
    bills.find(bill => bill.state === 'OPEN')
  if (next) {
    return { total: Money.of(next.total.cents), dueOn: next.dueOn }
  }
  const kept = card.origin === 'MANUAL' && card.balance.isZero()
  if (card.credit !== null || !kept) {
    return { total: openBillOf(card), dueOn: null }
  }
  const posted = await deps.transactions.all(tenantId, {
    accountIds: [card.id],
    from: addDays(day, -HISTORY_DAYS),
    to: day,
  })
  const owed = posted.reduce((sum, item) => sum - item.amount.cents, 0)
  return { total: Money.of(Math.max(0, owed)), dueOn: null }
}

export type CardDues = ReadonlyMap<string, CardDue>

export async function cardDues(
  deps: TimelineDeps,
  tenantId: string,
  accounts: readonly Account[],
  day: LocalDate,
): Promise<CardDues> {
  const cards = accounts.filter(account => account.type === 'CREDIT_CARD')
  const dues = await Promise.all(
    cards.map(card => dueOf(deps, tenantId, card, day)),
  )
  return new Map(cards.map((card, index) => [card.id, dues[index] as CardDue]))
}

export function makeGetCardTimeline(deps: TimelineDeps) {
  return async function getCardTimeline(
    tenantId: string,
    accountId: string,
  ): Promise<CardTimelineView> {
    const card = required(
      await deps.accounts.findById(tenantId, accountId),
      'Account',
    )
    if (card.type !== 'CREDIT_CARD') {
      throw new ValidationError('Only a credit card has bills.')
    }
    const entity = await requireEntityById(
      deps.entities,
      tenantId,
      card.entityId,
    )
    const timeline = await timelineOf(
      deps,
      tenantId,
      card,
      today(deps.clock.now()),
    )
    return {
      accountId: card.id,
      name: card.name,
      suffix: card.numberSuffix,
      entityKind: entity.kind,
      ...timeline,
    }
  }
}
