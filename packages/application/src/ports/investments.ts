import { type LocalDate, type Money } from '@cashdeck/domain'

export const INVESTMENT_KINDS = [
  'FIXED_INCOME',
  'FUND',
  'EQUITY',
  'ETF',
  'PENSION',
  'STRUCTURED',
  'OTHER',
] as const
export type InvestmentKind = (typeof INVESTMENT_KINDS)[number]

export const INVESTMENT_STATUSES = ['ACTIVE', 'PENDING', 'CLOSED'] as const
export type InvestmentStatus = (typeof INVESTMENT_STATUSES)[number]

// How the issuer quotes the yield: 102 percent of CDI, or IPCA plus 6.5.
export type InvestmentRate = {
  percent: number | null
  index: string | null
  fixedAnnual: number | null
}

type InvestmentDetails = {
  externalId: string
  name: string
  kind: InvestmentKind
  // The provider's own label, such as CDB, LCI, STOCK or INVESTMENT_FUND.
  subtype: string | null
  issuer: string | null
  status: InvestmentStatus
  quantity: number | null
  rate: InvestmentRate | null
  lastMonthRate: number | null
  lastTwelveMonthsRate: number | null
  dueOn: LocalDate | null
  valuedOn: LocalDate | null
}

// A position as the provider reports it. The balance is net of taxes and
// fees; profit is null when the provider leaves it out. The code is a B3
// ticker for stocks and ETFs, and the unit price is the current one.
export type ProviderInvestment = InvestmentDetails & {
  balanceCents: number
  investedCents: number | null
  profitCents: number | null
  currency: string
  code: string | null
  unitPrice: number | null
}

export type InvestmentPosition = InvestmentDetails & {
  id: string
  tenantId: string
  entityId: string
  connectionId: string
  institutionId: string
  balance: Money
  invested: Money | null
  profit: Money | null
  syncedAt: Date
}

export const MOVEMENT_KINDS = [
  'BUY',
  'SELL',
  'INCOME',
  'TAX',
  'TRANSFER',
  'OTHER',
] as const
export type MovementKind = (typeof MOVEMENT_KINDS)[number]

// The amount is always positive; the kind says which way the money went.
export type ProviderMovement = {
  externalId: string
  kind: MovementKind
  occurredOn: LocalDate
  amountCents: number
  quantity: number | null
  unitPrice: number | null
}

export type InvestmentMovement = ProviderMovement & {
  id: string
  tenantId: string
  investmentId: string
}

// What a position was worth at the end of a day. An estimated one is
// rebuilt from market prices, before the position was first synced.
export type InvestmentSnapshot = {
  tenantId: string
  investmentId: string
  day: LocalDate
  balanceCents: number
  estimated: boolean
}

export interface InvestmentRepository {
  // One per connection and external id; a known one is overwritten and keeps
  // its id.
  saveAll(positions: readonly InvestmentPosition[]): Promise<void>
  list(tenantId: string): Promise<InvestmentPosition[]>
  // Drops the movements and snapshots of those positions too.
  deleteByConnection(tenantId: string, connectionId: string): Promise<void>
  // One per position and external id; a known one keeps its id.
  saveMovements(movements: readonly InvestmentMovement[]): Promise<void>
  listMovements(
    tenantId: string,
    investmentId?: string,
  ): Promise<InvestmentMovement[]>
  // One per position and day: a real snapshot replaces any, an estimated one
  // is only written on a day that has none.
  saveSnapshots(snapshots: readonly InvestmentSnapshot[]): Promise<void>
  // The snapshots from `from` to `to`, plus the last one before `from` of
  // each position, so the value on `from` is known.
  listSnapshots(
    tenantId: string,
    range: { from: LocalDate; to: LocalDate },
    investmentId?: string,
  ): Promise<InvestmentSnapshot[]>
  // The oldest snapshot day of each position that has one.
  firstSnapshotDays(tenantId: string): Promise<Map<string, LocalDate>>
}

export type DailyValue = { day: LocalDate; value: number }

export const CDI_INDEX = 'CDI'

// Daily rates of a market index, in percent per day as the central bank
// publishes them.
export interface IndexRateRepository {
  save(index: string, rates: readonly DailyValue[]): Promise<void>
  list(
    index: string,
    range: { from: LocalDate; to: LocalDate },
  ): Promise<DailyValue[]>
  lastDay(index: string): Promise<LocalDate | null>
}

export interface MarketData {
  // Closing prices of a B3 ticker on each trading day of the range.
  dailyCloses(
    ticker: string,
    from: LocalDate,
    to: LocalDate,
  ): Promise<DailyValue[]>
  cdiRates(from: LocalDate, to: LocalDate): Promise<DailyValue[]>
}
