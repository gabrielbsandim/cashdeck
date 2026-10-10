import { type EntityKind, Money } from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type InvestmentPositionView,
  type InvestmentsView,
} from '@/dtos/investments'
import {
  type InvestmentMovement,
  type InvestmentPosition,
  type MovementKind,
} from '@/ports/investments'
import { type Institution } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { logoView } from '@/use-cases/finance'
import { requireEntity } from '@/use-cases/shared'

type InvestmentDeps = Pick<Deps, 'entities' | 'institutions' | 'investments'>

// Totals add up the positions held in reais; others are listed only.
export const TOTAL_CURRENCY = 'BRL'

// Money put into a position counts up, money taken out counts down.
const FLOW_SIGNS: Partial<Record<MovementKind, number>> = { BUY: 1, SELL: -1 }

export const signedFlow = (movement: InvestmentMovement) =>
  (FLOW_SIGNS[movement.kind] ?? 0) * movement.amountCents

export function groupByPosition<T extends { investmentId: string }>(
  rows: readonly T[],
) {
  return new Map(groupBy(rows, row => row.investmentId))
}

// Without an amount from the provider, what the movements put in, net.
function investedOf(
  position: InvestmentPosition,
  movements: readonly InvestmentMovement[],
) {
  if (position.invested) {
    return position.invested
  }
  const net = movements.reduce((sum, row) => sum + signedFlow(row), 0)
  return net > 0 ? Money.of(net, position.balance.currency) : null
}

// The reported profit first, else what the balance gained over the amount
// put in.
function yieldOf(position: InvestmentPosition) {
  const { invested } = position
  if (!invested) {
    return { profit: position.profit, percent: null }
  }
  const profit = position.profit ?? position.balance.subtract(invested)
  return {
    profit,
    percent:
      invested.cents > 0
        ? Math.round((profit.cents / invested.cents) * 10_000) / 100
        : null,
  }
}

const totalOf = (values: ReadonlyArray<{ cents: number } | null>) =>
  money(
    Money.of(
      values.reduce((sum, value) => sum + (value?.cents ?? 0), 0),
      TOTAL_CURRENCY,
    ),
  )

function groupBy<T, K>(rows: readonly T[], keyOf: (row: T) => K) {
  const groups = new Map<K, T[]>()
  for (const row of rows) {
    groups.set(keyOf(row), [...(groups.get(keyOf(row)) ?? []), row])
  }
  return [...groups.entries()]
}

const byTotal = (a: { total: { cents: number } }, b: typeof a) =>
  b.total.cents - a.total.cents

export function positionView(
  stored: InvestmentPosition,
  entityKind: EntityKind,
  institution: Institution | null,
  movements: readonly InvestmentMovement[],
): InvestmentPositionView {
  const position = { ...stored, invested: investedOf(stored, movements) }
  const { profit, percent } = yieldOf(position)
  return {
    id: position.id,
    entityKind,
    institutionId: position.institutionId,
    institution: institution?.name ?? '',
    logo: logoView(institution),
    name: position.name,
    kind: position.kind,
    subtype: position.subtype,
    issuer: position.issuer,
    status: position.status === 'PENDING' ? 'PENDING' : 'ACTIVE',
    balance: money(position.balance),
    invested: position.invested && money(position.invested),
    profit: profit && money(profit),
    profitPercent: percent,
    quantity: position.quantity,
    rate: position.rate,
    lastMonthRate: position.lastMonthRate,
    lastTwelveMonthsRate: position.lastTwelveMonthsRate,
    dueOn: position.dueOn,
    valuedOn: position.valuedOn,
  }
}

export async function institutionsOf(
  deps: Pick<Deps, 'institutions'>,
  tenantId: string,
  positions: readonly InvestmentPosition[],
) {
  const found = new Map<string, Institution | null>()
  for (const id of new Set(positions.map(row => row.institutionId))) {
    found.set(id, await deps.institutions.findById(tenantId, id))
  }
  return found
}

// The positions held by the entities in scope, with the kind of each owner.
export async function heldPositions(
  deps: Pick<Deps, 'entities' | 'investments'>,
  tenantId: string,
  kind?: EntityKind,
) {
  const entities = kind
    ? [await requireEntity(deps.entities, tenantId, kind)]
    : await deps.entities.list(tenantId)
  const kinds = new Map(entities.map(entity => [entity.id, entity.kind]))
  const held = (await deps.investments.list(tenantId)).filter(
    position => kinds.has(position.entityId) && position.status !== 'CLOSED',
  )
  return { held, kinds }
}

export function makeListInvestments(deps: InvestmentDeps) {
  return async function listInvestments(
    tenantId: string,
    kind?: EntityKind,
  ): Promise<InvestmentsView> {
    const { held, kinds } = await heldPositions(deps, tenantId, kind)
    const institutions = await institutionsOf(deps, tenantId, held)
    const movements = groupByPosition(
      await deps.investments.listMovements(tenantId),
    )
    const positions = held
      .map(position =>
        positionView(
          position,
          kinds.get(position.entityId) as EntityKind,
          institutions.get(position.institutionId) ?? null,
          movements.get(position.id) ?? [],
        ),
      )
      .sort(
        (a, b) =>
          b.balance.cents - a.balance.cents || a.name.localeCompare(b.name),
      )
    const counted = positions.filter(
      position => position.balance.currency === TOTAL_CURRENCY,
    )
    const syncedAt = held
      .map(position => position.syncedAt.toISOString())
      .sort()
      .at(-1)
    return {
      total: totalOf(counted.map(position => position.balance)),
      invested: totalOf(counted.map(position => position.invested)),
      profit: totalOf(counted.map(position => position.profit)),
      syncedAt: syncedAt ?? null,
      institutions: groupBy(counted, position => position.institutionId)
        .map(([institutionId, rows]) => {
          const [first] = rows as [InvestmentPositionView]
          return {
            institutionId,
            institution: first.institution,
            logo: first.logo,
            total: totalOf(rows.map(row => row.balance)),
            count: rows.length,
          }
        })
        .sort(byTotal),
      kinds: groupBy(counted, position => position.kind)
        .map(([kind, rows]) => ({
          kind,
          total: totalOf(rows.map(row => row.balance)),
          count: rows.length,
        }))
        .sort(byTotal),
      positions,
    }
  }
}
