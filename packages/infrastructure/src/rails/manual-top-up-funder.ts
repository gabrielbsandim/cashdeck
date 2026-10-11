import {
  type FundingRequest,
  type FundingResult,
  type RailStatusScope,
  type ReserveFunder,
} from '@cashdeck/application'

export type ManualTopUpFunderDeps = {
  balance: { balanceCents(scope: RailStatusScope): Promise<number> }
}

export const TOP_UP_REASON =
  'The Asaas balance does not cover these bills; top it up by Pix.'

// No provider moves money into Asaas, so the round only measures the balance
// and a shortfall fails, sending the bills to assisted until the user tops up.
export class ManualTopUpFunder implements ReserveFunder {
  constructor(private readonly deps: ManualTopUpFunderDeps) {}

  availableCents(scope: RailStatusScope): Promise<number> {
    return this.deps.balance.balanceCents(scope)
  }

  async fund(_request: FundingRequest): Promise<FundingResult> {
    return { outcome: 'FAILED', externalId: null, reason: TOP_UP_REASON }
  }
}
