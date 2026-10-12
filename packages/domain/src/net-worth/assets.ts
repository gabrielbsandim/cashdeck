import { type LocalDate } from '@/calendar/local-date'
import { Money } from '@/money/money'

export const ASSET_KINDS = ['PROPERTY', 'VEHICLE', 'OTHER'] as const
export type AssetKind = (typeof ASSET_KINDS)[number]

export type Valuation = { readonly day: LocalDate; readonly cents: number }

// A good priced now and then, by hand or from a price table.
export type ValuedAsset = {
  readonly kind: AssetKind
  readonly acquiredOn: LocalDate
  readonly soldOn: LocalDate | null
  readonly valuations: readonly Valuation[]
}

const byDay = (valuations: readonly Valuation[]) =>
  [...valuations].sort((a, b) => a.day.localeCompare(b.day))

// Before its first price it is worth that price, since it was already owned;
// nothing before it was bought or once it was sold.
export function assetValueOn(asset: ValuedAsset, day: LocalDate): Money {
  if (day < asset.acquiredOn) {
    return Money.zero()
  }
  if (asset.soldOn !== null && day >= asset.soldOn) {
    return Money.zero()
  }
  const sorted = byDay(asset.valuations)
  const known = sorted.filter(valuation => valuation.day <= day).at(-1)
  return Money.of((known ?? sorted[0])?.cents ?? 0)
}

// A new price replaces one already on that day.
export function withValuation(
  valuations: readonly Valuation[],
  valuation: Valuation,
): Valuation[] {
  return byDay([
    ...valuations.filter(known => known.day !== valuation.day),
    valuation,
  ])
}
