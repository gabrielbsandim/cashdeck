import {
  type FundingRequest,
  type FundingResult,
  type RailResult,
  type RailStatusScope,
  type ReserveFunder,
} from '@cashdeck/application'
import {
  type Credentials,
  requireCredentials,
} from '@/credentials/credential-resolver'
import { type PayoutInput } from '@/rails/mercado-pago-rail'

const PROVIDER = 'Reserve funding'

export type ReserveFunderDeps = {
  credentials: Credentials
  balance: { balanceCents(scope: RailStatusScope): Promise<number> }
  payouts: { payout(input: PayoutInput): Promise<RailResult> }
}

const OUTCOMES: Record<string, FundingResult['outcome']> = {
  PAID: 'PAID',
  FAILED: 'FAILED',
}

// The personal reserve sits in Mercado Pago and the bills are paid by Asaas:
// a payout sends Pix to the Asaas account key configured for the entity.
export class PixReserveFunder implements ReserveFunder {
  constructor(private readonly deps: ReserveFunderDeps) {}

  availableCents(scope: RailStatusScope): Promise<number> {
    return this.deps.balance.balanceCents(scope)
  }

  async fund(request: FundingRequest): Promise<FundingResult> {
    const scope = { tenantId: request.tenantId, entityId: request.entityId }
    const { ASAAS_PIX_KEY } = await requireCredentials(
      this.deps.credentials,
      PROVIDER,
      ['ASAAS_PIX_KEY'],
      scope,
    )
    const result = await this.deps.payouts.payout({
      scope,
      pixKey: ASAAS_PIX_KEY,
      amountCents: request.amountCents,
      description: request.description,
      idempotencyKey: request.idempotencyKey,
    })
    return {
      outcome: OUTCOMES[result.outcome] ?? 'SUBMITTED',
      externalId: result.externalId ?? null,
      reason: result.reason ?? null,
    }
  }
}
