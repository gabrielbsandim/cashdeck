import { type PaymentMethod, type RailId } from '@cashdeck/domain'
import { type RailResult } from '@/ports/payment-rail'

export type RailStatusScope = { tenantId: string; entityId: string }

export type RailStatus = RailResult & {
  endToEndId: string | null
  settledAt: string | null
}

// Reconciliation asks the rail that took a payment for its final state, using
// the external id the rail returned from `pay`.
export interface RailStatusReader {
  readonly id: RailId
  status(externalId: string, scope: RailStatusScope): Promise<RailStatus>
  // Finds a payment by the idempotency key sent with it, for a call whose
  // answer was lost; null when the rail has no such payment.
  findByReference?(
    reference: { idempotencyKey: string; method: PaymentMethod },
    scope: RailStatusScope,
  ): Promise<RailStatus | null>
}
