import {
  type AttemptOutcome,
  type Bill,
  type BillKind,
  type EntityKind,
} from '@cashdeck/domain'
import {
  type ProviderCheck,
  ProviderNotConfiguredError,
  type RailResult,
  type RailStatus,
} from '@cashdeck/application'
import { type CredentialScope } from '@/credentials/credential-resolver'

export type Coverage = {
  entityKinds: readonly EntityKind[]
  billKinds: readonly BillKind[]
}

export function covers(
  coverage: Coverage,
  kind: BillKind,
  entityKind: EntityKind,
): boolean {
  return (
    coverage.entityKinds.includes(entityKind) &&
    coverage.billKinds.includes(kind)
  )
}

export function scopeOf(bill: Bill): CredentialScope {
  return { tenantId: bill.tenantId, entityId: bill.entityId }
}

export function failed(reason: string): RailResult {
  return { outcome: 'FAILED', reason }
}

export function outcomeFrom(
  table: Record<string, AttemptOutcome>,
  status: string | undefined,
  fallback: AttemptOutcome = 'SUBMITTED',
): AttemptOutcome {
  return (status && table[status]) || fallback
}

export function statusResult(
  outcome: AttemptOutcome,
  externalId: string,
  extra: Partial<RailStatus> = {},
): RailStatus {
  return {
    outcome,
    externalId,
    endToEndId: null,
    settledAt: null,
    reason: null,
    ...extra,
  }
}

export function splitExternalId(
  externalId: string,
  provider: string,
): [string, string] {
  const index = externalId.indexOf(':')
  if (index <= 0) {
    throw new Error(`${provider} does not know the payment "${externalId}".`)
  }
  return [externalId.slice(0, index), externalId.slice(index + 1)]
}

export async function checkWith(
  provider: string,
  probe: () => Promise<void>,
): Promise<ProviderCheck> {
  try {
    await probe()
    return { ok: true, message: null }
  } catch (error) {
    if (error instanceof ProviderNotConfiguredError) {
      return { ok: false, message: error.message }
    }
    const detail = error instanceof Error ? error.message : String(error)
    return { ok: false, message: `${provider} check failed: ${detail}` }
  }
}
