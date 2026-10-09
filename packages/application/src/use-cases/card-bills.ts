import {
  type Account,
  addDays,
  type CreditLine,
  daysBetween,
  type EntityKind,
  type LocalDate,
  Money,
  shiftMonth,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type CardBillState, type CardBillsView } from '@/dtos/insights'
import { type CardBill } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { insightScope } from '@/use-cases/insights'
import { lastDay, monthOf, today } from '@/use-cases/shared'

type CardBillDeps = Pick<Deps, 'entities' | 'accounts' | 'cardBills' | 'clock'>

const MAX_BILLS = 12
// Closing to due when neither the bill nor the card says when it closes.
const DEFAULT_GAP_DAYS = 7

type Dated = {
  closesOn: LocalDate
  reportedClosesOn: LocalDate | null
  dueOn: LocalDate
  total: Money
  minimum: Money | null
}

function gapOf(credit: CreditLine | null): number {
  if (!credit?.closesOn || !credit.dueOn) {
    return DEFAULT_GAP_DAYS
  }
  return daysBetween(credit.closesOn, credit.dueOn)
}

function monthBefore(day: LocalDate): LocalDate {
  const month = shiftMonth(monthOf(day), -1)
  const sameDay = `${month}-${day.slice(8)}`
  const last = lastDay(month)
  return sameDay < last ? sameDay : last
}

function stateOf(bill: Dated, day: LocalDate): CardBillState {
  if (day <= bill.closesOn) {
    return 'OPEN'
  }
  return day <= bill.dueOn ? 'CLOSED' : 'PAST'
}

// The bill the issuer is still filling, worth what the card owes now.
function openBill(card: Account, gap: number): Dated | null {
  const credit = card.credit
  if (!credit?.dueOn) {
    return null
  }
  return {
    closesOn: credit.closesOn ?? addDays(credit.dueOn, -gap),
    reportedClosesOn: credit.closesOn,
    dueOn: credit.dueOn,
    total: Money.of(Math.max(0, -card.balance.cents), card.balance.currency),
    minimum: null,
  }
}

function billsOf(card: Account, stored: readonly CardBill[], day: LocalDate) {
  const gap = gapOf(card.credit)
  const dated: Dated[] = stored.map(bill => ({
    closesOn: bill.closesOn ?? addDays(bill.dueOn, -gap),
    reportedClosesOn: bill.closesOn,
    dueOn: bill.dueOn,
    total: bill.total,
    minimum: bill.minimum,
  }))
  const open = openBill(card, gap)
  const known = new Set(dated.map(bill => bill.dueOn))
  const bills = [...(open && !known.has(open.dueOn) ? [open] : []), ...dated]
    .sort((a, b) => b.dueOn.localeCompare(a.dueOn))
    .slice(0, MAX_BILLS)
  return bills.map((bill, index) => {
    const previous = bills[index + 1]?.closesOn ?? monthBefore(bill.closesOn)
    return {
      closesOn: bill.reportedClosesOn,
      dueOn: bill.dueOn,
      total: money(bill.total),
      minimum: bill.minimum ? money(bill.minimum) : null,
      state: stateOf(bill, day),
      range: { from: addDays(previous, 1), to: bill.closesOn },
    }
  })
}

export function makeListCardBills(deps: CardBillDeps) {
  return async function listCardBills(
    tenantId: string,
    kind?: EntityKind,
  ): Promise<CardBillsView> {
    const day = today(deps.clock.now())
    const scope = await insightScope(deps, tenantId, kind)
    const cards = scope.accounts.filter(
      account => account.type === 'CREDIT_CARD',
    )
    if (cards.length === 0) {
      return { cards: [] }
    }
    const stored = await deps.cardBills.list(
      tenantId,
      cards.map(card => card.id),
    )
    const kinds = new Map(
      scope.entities.map(entity => [entity.id, entity.kind]),
    )
    return {
      cards: cards.map(card => ({
        accountId: card.id,
        name: card.name,
        suffix: card.numberSuffix,
        entityKind: kinds.get(card.entityId) as EntityKind,
        bills: billsOf(
          card,
          stored.filter(bill => bill.accountId === card.id),
          day,
        ),
      })),
    }
  }
}
