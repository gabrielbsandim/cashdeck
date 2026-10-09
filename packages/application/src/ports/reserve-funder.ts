import { type RailStatusScope } from '@/ports/rail-status'

export type FundingRequest = {
  tenantId: string
  entityId: string
  amountCents: number
  idempotencyKey: string
  description: string
}

export type FundingResult = {
  outcome: 'SUBMITTED' | 'PAID' | 'FAILED'
  externalId: string | null
  reason: string | null
}

// Moves money from the personal reserve to the account that pays the bills,
// and reads what that account already holds so only the shortfall moves.
export interface ReserveFunder {
  availableCents(scope: RailStatusScope): Promise<number>
  fund(request: FundingRequest): Promise<FundingResult>
}
