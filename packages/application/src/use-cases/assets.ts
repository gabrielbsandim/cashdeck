import {
  type AssetKind,
  assetValueOn,
  type EntityKind,
  installmentIn,
  isRentalBill,
  type LocalDate,
  loanBalanceOn,
  Money,
  netWorthChange,
  type Rental,
  rentCharge,
  ValidationError,
  type Valuation,
  withValuation,
} from '@cashdeck/domain'
import {
  type AssetsView,
  type AssetView,
  type CreateAssetInput,
  type RentalView,
  type UpdateAssetInput,
} from '@/dtos/assets'
import { money } from '@/dtos/common'
import { type FipeVehicle, type VehiclePriceHistory } from '@/ports/investments'
import { loadBillLines, type StoredBillLines } from '@/use-cases/bill-lines'
import { type Deps } from '@/use-cases/deps'
import { LOANS_COLLECTION, loadLoans, type StoredLoan } from '@/use-cases/loans'
import { requireEntity, required, today } from '@/use-cases/shared'

export const ASSETS_COLLECTION = 'assets'

export type StoredAsset = {
  id: string
  entityId: string
  entity: EntityKind
  kind: AssetKind
  name: string
  acquiredOn: LocalDate
  soldOn: LocalDate | null
  valuations: Valuation[]
  fipe: FipeVehicle | null
  loanId: string | null
  // Missing on goods stored before renting out was tracked.
  rental?: Rental | null
  createdAt: string
}

// What the asset view reads besides the asset itself.
export type AssetContext = {
  loans: ReadonlyMap<string, StoredLoan>
  bills: readonly StoredBillLines[]
}

type AssetDeps = Pick<
  Deps,
  'entities' | 'documents' | 'vehiclePrices' | 'clock' | 'ids'
>

const ORDER: Record<AssetKind, number> = { PROPERTY: 0, VEHICLE: 1, OTHER: 2 }

export const loadAssets = (deps: Pick<Deps, 'documents'>, tenantId: string) =>
  deps.documents.list<StoredAsset>(tenantId, ASSETS_COLLECTION)

// A table price holds from the first day of its reference month.
const fromTable = (history: VehiclePriceHistory): Valuation[] =>
  history.prices.map(price => ({
    day: `${price.month}-01`,
    cents: price.cents,
  }))

const latestBill = (rental: Rental, bills: readonly StoredBillLines[]) =>
  bills
    .filter(bill => isRentalBill(rental, bill.payee))
    .sort((a, b) => a.dueDate.localeCompare(b.dueDate))
    .at(-1)

export function rentalView(
  rental: Rental,
  loan: StoredLoan | undefined,
  bills: readonly StoredBillLines[],
): RentalView {
  const base = {
    rent: money(Money.of(rental.rent)),
    passThrough: [...rental.passThrough],
    billFrom: rental.billFrom,
  }
  const bill = latestBill(rental, bills)
  if (!bill) {
    return { ...base, charge: null }
  }
  const charge = rentCharge(rental, bill.lines, bill.total)
  const installment = loan
    ? installmentIn(loan, bill.dueDate.slice(0, 7))
    : null
  const owed = installment?.total ?? 0
  return {
    ...base,
    charge: {
      billId: bill.billId,
      dueDate: bill.dueDate,
      billTotal: money(Money.of(bill.total)),
      passedOn: charge.passedOn.map(line => ({
        description: line.description,
        amount: money(Money.of(line.cents)),
      })),
      total: money(Money.of(charge.total)),
      ownerCost: money(Money.of(charge.ownerCost)),
      attachmentId: bill.attachmentId,
      installment: installment ? money(Money.of(installment.total)) : null,
      result: money(Money.of(rental.rent - owed - charge.ownerCost)),
    },
  }
}

const merged = (valuations: readonly Valuation[], priced: Valuation[]) =>
  priced.reduce(withValuation, [...valuations])

export function assetView(
  asset: StoredAsset,
  context: AssetContext,
  day: LocalDate,
): AssetView {
  const value = assetValueOn(asset, day)
  const loan =
    asset.loanId === null ? undefined : context.loans.get(asset.loanId)
  const rental = asset.rental ?? null
  const owed = Money.of(loan ? loanBalanceOn(loan, day) : 0)
  // Create and update keep one value at least, none of them after today.
  const first = asset.valuations[0] as Valuation
  const latest = asset.valuations.filter(known => known.day <= day).at(-1)
  const change = netWorthChange(value, Money.of(first.cents))
  return {
    id: asset.id,
    entity: asset.entity,
    kind: asset.kind,
    name: asset.name,
    acquiredOn: asset.acquiredOn,
    soldOn: asset.soldOn,
    value: money(value),
    valuedOn: (latest as Valuation).day,
    change: { amount: money(change.amount), percent: change.percent },
    fipe: asset.fipe,
    loan: loan
      ? {
          id: loan.id,
          name: `${loan.lender} ${loan.contract}`,
          balance: money(owed),
        }
      : null,
    equity: money(value.subtract(owed)),
    rental: rental ? rentalView(rental, loan, context.bills) : null,
  }
}

export function makeAssets(deps: AssetDeps) {
  const day = () => today(deps.clock.now())

  async function find(tenantId: string, id: string) {
    return required(
      await deps.documents.get<StoredAsset>(tenantId, ASSETS_COLLECTION, id),
      'Asset',
    )
  }

  async function requireLoan(tenantId: string, loanId: string | null = null) {
    if (loanId === null) {
      return
    }
    required(
      await deps.documents.get<StoredLoan>(tenantId, LOANS_COLLECTION, loanId),
      'Loan',
    )
  }

  async function contextOf(tenantId: string): Promise<AssetContext> {
    const loans = await loadLoans(deps, tenantId)
    return {
      loans: new Map(loans.map(loan => [loan.id, loan])),
      bills: await loadBillLines(deps, tenantId),
    }
  }

  async function viewOf(tenantId: string, asset: StoredAsset) {
    return assetView(asset, await contextOf(tenantId), day())
  }

  async function list(tenantId: string): Promise<AssetsView> {
    const context = await contextOf(tenantId)
    const items = (await loadAssets(deps, tenantId))
      .sort(
        (a, b) => ORDER[a.kind] - ORDER[b.kind] || a.name.localeCompare(b.name),
      )
      .map(asset => assetView(asset, context, day()))
    const total = (pick: (item: AssetView) => number) =>
      money(Money.of(items.reduce((sum, item) => sum + pick(item), 0)))
    return {
      items,
      value: total(item => item.value.cents),
      loanDebt: total(item => item.loan?.balance.cents ?? 0),
      equity: total(item => item.equity.cents),
    }
  }

  async function create(
    tenantId: string,
    input: CreateAssetInput,
  ): Promise<AssetView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    await requireLoan(tenantId, input.loanId)
    const table = input.fipe
      ? await deps.vehiclePrices.history(input.fipe)
      : null
    const priced = table ? merged([], fromTable(table)) : []
    const valuations =
      input.value === undefined
        ? priced
        : withValuation(priced, { day: day(), cents: input.value })
    if (valuations.length === 0) {
      throw new ValidationError('The FIPE table has no price for that year.')
    }
    const asset: StoredAsset = {
      id: deps.ids.next(),
      entityId: entity.id,
      entity: entity.kind,
      kind: input.kind,
      // The schema asks for a name unless the FIPE table gives the model.
      name: input.name ?? (table as VehiclePriceHistory).model,
      acquiredOn: input.acquiredOn,
      soldOn: null,
      valuations,
      fipe: input.fipe ?? null,
      loanId: input.loanId,
      rental: input.rental,
      createdAt: deps.clock.now().toISOString(),
    }
    await deps.documents.put(tenantId, ASSETS_COLLECTION, asset.id, asset)
    return viewOf(tenantId, asset)
  }

  async function update(
    tenantId: string,
    id: string,
    input: UpdateAssetInput,
  ): Promise<AssetView> {
    const asset = await find(tenantId, id)
    await requireLoan(tenantId, input.loanId)
    if (input.valuedOn && input.valuedOn > day()) {
      throw new ValidationError('A value cannot hold from a future day.')
    }
    if (input.fipe && asset.kind !== 'VEHICLE') {
      throw new ValidationError('Only a vehicle has a FIPE code.')
    }
    const table = input.fipe
      ? await deps.vehiclePrices.history(input.fipe)
      : null
    // The old prices were another model's.
    const base = table ? merged([], fromTable(table)) : asset.valuations
    const valuations =
      input.value === undefined
        ? base
        : withValuation(base, {
            day: input.valuedOn ?? day(),
            cents: input.value,
          })
    if (valuations.length === 0) {
      throw new ValidationError('The FIPE table has no price for that year.')
    }
    const next: StoredAsset = {
      ...asset,
      name: input.name ?? table?.model ?? asset.name,
      acquiredOn: input.acquiredOn ?? asset.acquiredOn,
      fipe: input.fipe === undefined ? asset.fipe : input.fipe,
      loanId: input.loanId === undefined ? asset.loanId : input.loanId,
      soldOn: input.soldOn === undefined ? asset.soldOn : input.soldOn,
      rental:
        input.rental === undefined ? (asset.rental ?? null) : input.rental,
      valuations,
    }
    await deps.documents.put(tenantId, ASSETS_COLLECTION, id, next)
    return viewOf(tenantId, next)
  }

  async function remove(tenantId: string, id: string) {
    await find(tenantId, id)
    await deps.documents.delete(tenantId, ASSETS_COLLECTION, id)
    return { id }
  }

  // Monthly: each vehicle still owned takes the table's newest prices. One
  // the table no longer answers for keeps its last price.
  async function refreshPrices(tenantId: string) {
    const priced = (await loadAssets(deps, tenantId)).filter(
      asset => asset.fipe !== null && asset.soldOn === null,
    )
    let refreshed = 0
    for (const asset of priced) {
      const history = await deps.vehiclePrices
        .history(asset.fipe as FipeVehicle)
        .catch(() => null)
      if (!history) {
        continue
      }
      const valuations = merged(asset.valuations, fromTable(history))
      await deps.documents.put(tenantId, ASSETS_COLLECTION, asset.id, {
        ...asset,
        valuations,
      })
      refreshed += 1
    }
    return { refreshed, failed: priced.length - refreshed }
  }

  return { list, create, update, remove, refreshPrices }
}
