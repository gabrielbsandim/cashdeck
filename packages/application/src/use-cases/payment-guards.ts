import {
  type Bill,
  deviatesFromHistory,
  type PaymentAttempt,
  type RailId,
  recipientKeys,
} from '@cashdeck/domain'
import { type ConfirmationReason } from '@/dtos/bill'
import { ProviderNotConfiguredError } from '@/errors/errors'
import { type RailResult } from '@/ports/payment-rail'
import { type RailStatusReader } from '@/ports/rail-status'
import {
  type BillRepository,
  type IdempotencyStore,
  type PayeeDirectory,
  type PaymentSettings,
} from '@/ports/repositories'

const HISTORY_LIMIT = 50

export function failureReason(error: unknown): string {
  if (error instanceof ProviderNotConfiguredError) {
    return 'NOT_CONFIGURED'
  }
  if (error instanceof Error) {
    return error.message
  }
  return 'UNKNOWN_ERROR'
}

export type ConfirmationDeps = { payees: PayeeDirectory; bills: BillRepository }

export function makeConfirmationCheck(deps: ConfirmationDeps) {
  async function paidHistory(
    tenantId: string,
    bill: Bill,
    keys: readonly string[],
  ): Promise<number[]> {
    const paid = await deps.bills.listRecentPaid(
      tenantId,
      bill.entityId,
      HISTORY_LIMIT,
    )
    return paid
      .filter(other => other.id !== bill.id)
      .filter(other => recipientKeys(other).some(key => keys.includes(key)))
      .map(other => other.amount.cents)
  }

  return async function confirmationReasons(
    tenantId: string,
    bill: Bill,
    settings: PaymentSettings,
  ): Promise<ConfirmationReason[]> {
    const keys = recipientKeys(bill)
    const known = await Promise.all(
      keys.map(key => deps.payees.isKnown(tenantId, bill.entityId, key)),
    )
    const history = await paidHistory(tenantId, bill, keys)
    const threshold = settings.confirmAboveCents
    const checks: Array<[ConfirmationReason, boolean]> = [
      ['NEW_PAYEE', known.includes(false)],
      ['ABOVE_THRESHOLD', threshold !== null && bill.amount.cents > threshold],
      [
        'AMOUNT_DEVIATION',
        deviatesFromHistory(
          bill.amount.cents,
          history,
          settings.maxDeviationPercent,
        ),
      ],
    ]
    return checks.filter(([, hit]) => hit).map(([reason]) => reason)
  }
}

export type InFlightDeps = {
  idempotency: IdempotencyStore
  railStatus: ReadonlyMap<RailId, RailStatusReader>
}

export type ResolvedPayment = RailResult & { settledAt?: string | null }

// A payment whose answer was lost: the stored result wins, then the rail is
// asked by the idempotency key. Null means nobody knows yet, so it never repays.
export function makeResolveInFlight(deps: InFlightDeps) {
  async function lookup(
    tenantId: string,
    entityId: string,
    attempt: PaymentAttempt,
  ): Promise<ResolvedPayment | null> {
    const reader = deps.railStatus.get(attempt.rail)
    if (!reader?.findByReference) {
      return null
    }
    try {
      return await reader.findByReference(
        { idempotencyKey: attempt.idempotencyKey, method: attempt.method },
        { tenantId, entityId },
      )
    } catch {
      return null
    }
  }

  return async function resolveInFlight(
    tenantId: string,
    entityId: string,
    attempt: PaymentAttempt,
  ): Promise<ResolvedPayment | null> {
    const stored = await deps.idempotency.find<RailResult>(
      tenantId,
      attempt.idempotencyKey,
    )
    if (stored) {
      return stored
    }
    const found = await lookup(tenantId, entityId, attempt)
    if (found) {
      await deps.idempotency.save(
        tenantId,
        attempt.idempotencyKey,
        'payment',
        found,
      )
    }
    return found
  }
}
