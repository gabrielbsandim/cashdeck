import {
  type Account,
  addDays,
  type CreditLine,
  daysBetween,
  type LocalDate,
  type Money,
  openBillOf,
  shiftMonth,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type CardBillState } from '@/dtos/insights'
import { type CardBill } from '@/ports/records'
import { lastDay, monthOf } from '@/use-cases/shared'

export function sameDayIn(month: string, dayOfMonth: string): LocalDate {
  const sameDay = `${month}-${dayOfMonth}`
  const last = lastDay(month)
  return sameDay < last ? sameDay : last
}

export function latestDue(stored: readonly CardBill[]): LocalDate | null {
  return (
    stored
      .map(bill => bill.dueOn)
      .sort()
      .at(-1) ?? null
  )
}

// Issuers keep the due day fixed, so the cycle after the last known bill
// falls on the same day of a later month.
export function dueAfter(latest: LocalDate, day: LocalDate): LocalDate {
  let month = shiftMonth(monthOf(latest), 1)
  while (sameDayIn(month, latest.slice(8)) < day) {
    month = shiftMonth(month, 1)
  }
  return sameDayIn(month, latest.slice(8))
}

// A reported due date already behind us is the last bill, not the open one.
export function reportedDue(card: Account, day: LocalDate): LocalDate | null {
  const due = card.credit?.dueOn ?? null
  return due !== null && due >= day ? due : null
}

// The cycle after the newest date the issuer reported, stored or on the card.
export function projectedDue(
  card: Account,
  stored: readonly CardBill[],
  day: LocalDate,
): LocalDate | null {
  const known = [latestDue(stored), card.credit?.dueOn ?? null]
    .filter((due): due is LocalDate => due !== null)
    .sort()
    .at(-1)
  return known ? dueAfter(known, day) : null
}

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

// The bills a card reported plus its open one, newest first.
export function cardBillsOf(
  card: Account,
  stored: readonly CardBill[],
  day: LocalDate,
) {
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
