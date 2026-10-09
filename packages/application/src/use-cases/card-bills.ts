import {
  type Account,
  addDays,
  type CreditLine,
  daysBetween,
  type EntityKind,
  type LocalDate,
  type Money,
  openBillOf,
  shiftMonth,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type CardBillState, type CardBillsView } from '@/dtos/insights'
import { type CardBill } from '@/ports/records'
import { projectedDue, reportedDue, sameDayIn } from '@/use-cases/card-cycle'
import { type Deps } from '@/use-cases/deps'
import { insightScope } from '@/use-cases/insights'
import { monthOf, today } from '@/use-cases/shared'

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

// The card's own gap first, else the usual gap of the bills it reported.
function gapOf(credit: CreditLine | null, stored: readonly CardBill[]): number {
  if (credit?.closesOn && credit.dueOn) {
    return daysBetween(credit.closesOn, credit.dueOn)
  }
  const gaps = stored
    .flatMap(bill =>
      bill.closesOn ? [daysBetween(bill.closesOn, bill.dueOn)] : [],
    )
    .sort((a, b) => a - b)
  return gaps.at(Math.floor(gaps.length / 2)) ?? DEFAULT_GAP_DAYS
}

const monthBefore = (day: LocalDate) =>
  sameDayIn(shiftMonth(monthOf(day), -1), day.slice(8))

function stateOf(bill: Dated, day: LocalDate): CardBillState {
  if (day <= bill.closesOn) {
    return 'OPEN'
  }
  return day <= bill.dueOn ? 'CLOSED' : 'PAST'
}

// The bill the issuer is still filling. Without the issuer's dates it is the
// cycle after the last bill it reported.
function openBill(
  card: Account,
  stored: readonly CardBill[],
  gap: number,
  day: LocalDate,
): Dated | null {
  const reported = reportedDue(card, day)
  const dueOn = reported ?? projectedDue(card, stored, day)
  if (!dueOn) {
    return null
  }
  const reportedClosesOn = reported ? (card.credit?.closesOn ?? null) : null
  return {
    closesOn: reportedClosesOn ?? addDays(dueOn, -gap),
    reportedClosesOn,
    dueOn,
    total: openBillOf(card),
    minimum: null,
  }
}

function billsOf(card: Account, stored: readonly CardBill[], day: LocalDate) {
  const gap = gapOf(card.credit, stored)
  const dated: Dated[] = stored.map(bill => ({
    closesOn: bill.closesOn ?? addDays(bill.dueOn, -gap),
    reportedClosesOn: bill.closesOn,
    dueOn: bill.dueOn,
    total: bill.total,
    minimum: bill.minimum,
  }))
  const open = openBill(card, stored, gap, day)
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
