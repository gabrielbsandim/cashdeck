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
// fees; profit is null when the provider leaves it out.
export type ProviderInvestment = InvestmentDetails & {
  balanceCents: number
  investedCents: number | null
  profitCents: number | null
  currency: string
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

export interface InvestmentRepository {
  // One per connection and external id; a known one is overwritten and keeps
  // its id.
  saveAll(positions: readonly InvestmentPosition[]): Promise<void>
  list(tenantId: string): Promise<InvestmentPosition[]>
  deleteByConnection(tenantId: string, connectionId: string): Promise<void>
}
