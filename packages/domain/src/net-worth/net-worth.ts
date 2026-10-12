import { addDays, type LocalDate, shiftMonth } from '@/calendar/local-date'
import { type LoanStatement, loanBalanceOn } from '@/loans/loan'
import { Money } from '@/money/money'
import {
  type AssetKind,
  assetValueOn,
  type ValuedAsset,
} from '@/net-worth/assets'

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
  readonly realEstate: Money
  readonly vehicles: Money
  readonly otherAssets: Money
  readonly cardDebt: Money
  readonly loanDebt: Money
}

// What an entity owns and owes beyond its accounts and investments.
export type Belongings = {
  readonly assets: readonly ValuedAsset[]
  readonly loans: readonly LoanStatement[]
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
  const assets = sum([
    composition.cash,
    composition.investments,
    composition.realEstate,
    composition.vehicles,
    composition.otherAssets,
  ])
  const liabilities = composition.cardDebt.add(composition.loanDebt)
  return {
    on,
    ...composition,
    assets,
    liabilities,
    total: assets.subtract(liabilities),
  }
}

export function netWorthOn(
  day: LocalDate,
  today: LocalDate,
  accounts: readonly RolledBackAccount[],
  positions: readonly SnapshottedPosition[],
  belongings: Belongings = { assets: [], loans: [] },
): NetWorthPoint {
  const balances = (kind: NetWorthAccountKind) =>
    accounts
      .filter(account => account.kind === kind)
      .map(account => balanceAtEndOf(account, day))
  const owed = balances('CARD').map(balance =>
    Money.of(Math.max(0, -balance.cents)),
  )
  const worth = (kind: AssetKind) =>
    sum(
      belongings.assets
        .filter(asset => asset.kind === kind)
        .map(asset => assetValueOn(asset, day)),
    )
  return netWorthPoint(day, {
    cash: sum(balances('CASH')),
    investments: sum([
      ...balances('INVESTMENT'),
      ...positions.map(position => positionValueOn(position, day, today)),
    ]),
    realEstate: worth('PROPERTY'),
    vehicles: worth('VEHICLE'),
    otherAssets: worth('OTHER'),
    cardDebt: sum(owed),
    loanDebt: sum(
      belongings.loans.map(loan => Money.of(loanBalanceOn(loan, day))),
    ),
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
