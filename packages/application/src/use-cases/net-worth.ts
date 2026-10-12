import {
  type Account,
  type AccountType,
  addDays,
  type Belongings,
  type FinancialEntity,
  type LocalDate,
  monthEnds,
  Money,
  type NetWorthAccountKind,
  netWorthChange,
  netWorthOn,
  type NetWorthPoint,
  type RolledBackAccount,
  type SnapshottedPosition,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import { type NetWorthQuery, type NetWorthView } from '@/dtos/net-worth'
import { type InvestmentPosition } from '@/ports/investments'
import { loadAssets } from '@/use-cases/assets'
import { type Deps } from '@/use-cases/deps'
import { loadLoans } from '@/use-cases/loans'
import { requireEntity, today } from '@/use-cases/shared'

type NetWorthDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'transactions'
  | 'investments'
  | 'documents'
  | 'clock'
>

const KIND_OF: Record<AccountType, NetWorthAccountKind> = {
  CHECKING: 'CASH',
  SAVINGS: 'CASH',
  WALLET: 'CASH',
  INVESTMENT: 'INVESTMENT',
  CREDIT_CARD: 'CARD',
}

const CURRENCY = 'BRL'
const YEAR_MONTHS = 12

type EntityHoldings = {
  kind: FinancialEntity['kind']
  accounts: RolledBackAccount[]
  positions: SnapshottedPosition[]
  belongings: Belongings
}

const compositionView = (point: NetWorthPoint) => ({
  cash: money(point.cash),
  investments: money(point.investments),
  realEstate: money(point.realEstate),
  vehicles: money(point.vehicles),
  otherAssets: money(point.otherAssets),
  cardDebt: money(point.cardDebt),
  loanDebt: money(point.loanDebt),
  assets: money(point.assets),
  liabilities: money(point.liabilities),
  total: money(point.total),
})

const changeView = (current: NetWorthPoint, previous: NetWorthPoint) => {
  const change = netWorthChange(current.total, previous.total)
  return { amount: money(change.amount), percent: change.percent }
}

// Past balances are today's rolled back by the transactions booked since;
// past investments are their snapshots, estimated ones included.
export function makeNetWorthFromBalancesAndSnapshots(deps: NetWorthDeps) {
  async function scopeOf(tenantId: string, kind?: FinancialEntity['kind']) {
    if (kind) {
      return [await requireEntity(deps.entities, tenantId, kind)]
    }
    return deps.entities.list(tenantId)
  }

  async function accountsOf(
    tenantId: string,
    entityId: string,
    from: LocalDate,
    day: LocalDate,
  ) {
    const owned = (await deps.accounts.listByEntity(tenantId, entityId)).filter(
      account => account.balance.currency === CURRENCY,
    )
    const booked = await deps.transactions.all(tenantId, {
      accountIds: owned.map(account => account.id),
      from,
      to: day,
    })
    return owned.map(
      (account: Account): RolledBackAccount => ({
        kind: KIND_OF[account.type],
        balance: account.balance,
        // A purchase abroad stored in its own currency cannot roll back a
        // balance kept in reais.
        movements: booked
          .filter(
            tx =>
              tx.accountId === account.id &&
              !tx.provisional &&
              tx.amount.currency === account.balance.currency,
          )
          .map(tx => ({ on: tx.bookedOn, amount: tx.amount })),
      }),
    )
  }

  async function valuation(tenantId: string, from: LocalDate, day: LocalDate) {
    const snapshots = await deps.investments.listSnapshots(tenantId, {
      from,
      to: day,
    })
    return (position: InvestmentPosition): SnapshottedPosition => ({
      current: position.status === 'CLOSED' ? Money.zero() : position.balance,
      snapshots: snapshots
        .filter(snapshot => snapshot.investmentId === position.id)
        .map(snapshot => ({ day: snapshot.day, cents: snapshot.balanceCents })),
    })
  }

  return async function netWorth(
    tenantId: string,
    query: NetWorthQuery,
  ): Promise<NetWorthView> {
    const day = today(deps.clock.now())
    const ends = monthEnds(day, Math.max(query.months, YEAR_MONTHS))
    const first = ends[0] as LocalDate
    const entities = await scopeOf(tenantId, query.entity)
    const held = (await deps.investments.list(tenantId)).filter(
      position => position.balance.currency === CURRENCY,
    )
    const valued = await valuation(tenantId, first, day)
    const owned = await loadAssets(deps, tenantId)
    const owed = await loadLoans(deps, tenantId)
    const holdings: EntityHoldings[] = []
    for (const entity of entities) {
      holdings.push({
        kind: entity.kind,
        accounts: await accountsOf(tenantId, entity.id, addDays(first, 1), day),
        positions: held
          .filter(position => position.entityId === entity.id)
          .map(valued),
        belongings: {
          assets: owned.filter(asset => asset.entityId === entity.id),
          loans: owed.filter(loan => loan.entityId === entity.id),
        },
      })
    }
    const accounts = holdings.flatMap(entity => entity.accounts)
    const positions = holdings.flatMap(entity => entity.positions)
    const belongings = {
      assets: holdings.flatMap(entity => entity.belongings.assets),
      loans: holdings.flatMap(entity => entity.belongings.loans),
    }
    const points = [...ends, day].map(on =>
      netWorthOn(on, day, accounts, positions, belongings),
    )
    const current = points.at(-1) as NetWorthPoint
    return {
      asOf: day,
      current: compositionView(current),
      fromLastMonth: changeView(current, points.at(-2) as NetWorthPoint),
      fromYearAgo: changeView(
        current,
        points.at(-1 - YEAR_MONTHS) as NetWorthPoint,
      ),
      entities: holdings.map(entity => ({
        kind: entity.kind,
        current: compositionView(
          netWorthOn(
            day,
            day,
            entity.accounts,
            entity.positions,
            entity.belongings,
          ),
        ),
      })),
      series: points.slice(-1 - query.months).map(point => ({
        on: point.on,
        assets: money(point.assets),
        liabilities: money(point.liabilities),
        total: money(point.total),
      })),
    }
  }
}
