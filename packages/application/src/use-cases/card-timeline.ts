import {
  addDays,
  type BillCycle,
  billPayment,
  chargesIn,
  cycleHolds,
  cyclesAfter,
  groupInstallments,
  type LocalDate,
  Money,
  type ProjectedInstallment,
  projectInstallments,
  type Transaction,
  ValidationError,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type CardTimelineView } from '@/dtos/insights'
import { cardBillsOf } from '@/use-cases/card-bills'
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

function knownView(
  bill: KnownBill,
  transactions: readonly Transaction[],
  day: LocalDate,
): TimelineBill {
  const total = Money.of(bill.total.cents)
  return {
    ...bill,
    payment:
      bill.state === 'OPEN'
        ? null
        : billPayment(cycleOf(bill), total, transactions, day),
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
    const day = today(deps.clock.now())
    const stored = await deps.cardBills.list(tenantId, [card.id])
    const known = cardBillsOf(card, stored, day).reverse()
    const header = {
      accountId: card.id,
      name: card.name,
      suffix: card.numberSuffix,
      entityKind: entity.kind,
    }
    const latest = known.at(-1)
    if (!latest) {
      return { ...header, bills: [], current: null }
    }
    const ahead = cyclesAfter(cycleOf(latest), MONTHS_AHEAD)
    const transactions = await deps.transactions.all(tenantId, {
      accountIds: [card.id],
      from: addDays(day, -HISTORY_DAYS),
      to: (ahead.at(-1) as BillCycle).closesOn,
    })
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
    const bills = [
      ...known.map(bill => knownView(bill, transactions, day)),
      ...forecasts.slice(0, last + 1),
    ]
    // The open bill is the latest known one or a cycle after it.
    const open = bills.findIndex(bill => bill.state === 'OPEN')
    return { ...header, bills, current: Math.max(open, known.length - 1) }
  }
}
