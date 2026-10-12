import { addDays, type LocalDate, shiftMonth } from '@/calendar/local-date'
import { Money } from '@/money/money'

export const NET_WORTH_ACCOUNT_KINDS = ['CASH', 'INVESTMENT', 'CARD'] as const
export type NetWorthAccountKind = (typeof NET_WORTH_ACCOUNT_KINDS)[number]

export type BookedMovement = { readonly on: LocalDate; readonly amount: Money }

// An account valued today, rolled back to a past day by undoing what was
// booked after it. A card balance is negative while something is owed.
export type RolledBackAccount = {
  readonly kind: NetWorthAccountKind
  readonly balance: Money
  readonly movements: readonly BookedMovement[]
}

export type DailySnapshot = { readonly day: LocalDate; readonly cents: number }

// A position valued today, and on a past day by its last snapshot then;
// nothing before its first snapshot.
export type SnapshottedPosition = {
  readonly current: Money
  readonly snapshots: readonly DailySnapshot[]
}

export type NetWorthComposition = {
  readonly cash: Money
  readonly investments: Money
  readonly cardDebt: Money
}

export type NetWorthPoint = NetWorthComposition & {
  readonly on: LocalDate
  readonly assets: Money
  readonly liabilities: Money
  readonly total: Money
}

export type NetWorthChange = {
  readonly amount: Money
  readonly percent: number | null
}

const sum = (amounts: readonly Money[]) =>
  amounts.reduce((total, amount) => total.add(amount), Money.zero())

export function balanceAtEndOf(
  account: RolledBackAccount,
  day: LocalDate,
): Money {
  const later = account.movements.filter(movement => movement.on > day)
  return account.balance.subtract(sum(later.map(movement => movement.amount)))
}

export function positionValueOn(
  position: SnapshottedPosition,
  day: LocalDate,
  today: LocalDate,
): Money {
  if (day >= today) {
    return position.current
  }
  const known = position.snapshots
    .filter(snapshot => snapshot.day <= day)
    .sort((a, b) => a.day.localeCompare(b.day))
    .at(-1)
  return Money.of(known?.cents ?? 0)
}

export function netWorthPoint(
  on: LocalDate,
  composition: NetWorthComposition,
): NetWorthPoint {
  const assets = composition.cash.add(composition.investments)
  return {
    on,
    ...composition,
    assets,
    liabilities: composition.cardDebt,
    total: assets.subtract(composition.cardDebt),
  }
}

export function netWorthOn(
  day: LocalDate,
  today: LocalDate,
  accounts: readonly RolledBackAccount[],
  positions: readonly SnapshottedPosition[],
): NetWorthPoint {
  const balances = (kind: NetWorthAccountKind) =>
    accounts
      .filter(account => account.kind === kind)
      .map(account => balanceAtEndOf(account, day))
  const owed = balances('CARD').map(balance =>
    Money.of(Math.max(0, -balance.cents)),
  )
  return netWorthPoint(day, {
    cash: sum(balances('CASH')),
    investments: sum([
      ...balances('INVESTMENT'),
      ...positions.map(position => positionValueOn(position, day, today)),
    ]),
    cardDebt: sum(owed),
  })
}

// The last day of each of the `months` months before the current one,
// oldest first.
export function monthEnds(today: LocalDate, months: number): LocalDate[] {
  const current = today.slice(0, 7)
  return Array.from({ length: months }, (_, index) =>
    addDays(`${shiftMonth(current, index - months + 1)}-01`, -1),
  )
}

export function netWorthChange(
  current: Money,
  previous: Money,
): NetWorthChange {
  const amount = current.subtract(previous)
  if (previous.isZero()) {
    return { amount, percent: null }
  }
  return {
    amount,
    percent: Math.round((amount.cents / Math.abs(previous.cents)) * 1000) / 10,
  }
}
