import { createHash, timingSafeEqual } from 'node:crypto'
import { UnauthorizedError, type WebhookDelivery } from '@cashdeck/application'
import { type Credentials } from '@/credentials/credential-resolver'

// Header the app asks providers to send back when they let us pick one.
export const WEBHOOK_TOKEN_HEADER = 'x-cashdeck-webhook-token'

const digest = (value: string) => createHash('sha256').update(value).digest()

// Hashing first gives both sides the same length, so the comparison never
// leaks the secret length.
export function sameSecret(given: string, expected: string): boolean {
  return timingSafeEqual(digest(given), digest(expected))
}

export function bodyId(raw: string): string {
  return digest(raw).toString('hex')
}

// `?entity=<entityId>` picks `NAME@entityId` before `NAME` and the environment,
// for providers whose accounts are per entity; a missing secret refuses.
export async function webhookSecret(
  credentials: Credentials,
  name: string,
  tenantId: string,
  delivery: WebhookDelivery,
): Promise<string> {
  const entityId = delivery.query.entity || undefined
  const secret = await credentials.get(name, { tenantId, entityId })
  if (!secret) {
    throw new UnauthorizedError('Webhook secret is not configured.')
  }
  return secret
}

export function requireSame(given: string | undefined, expected: string) {
  if (!sameSecret(given ?? '', expected)) {
    throw new UnauthorizedError('Invalid webhook credentials.')
  }
}

export type JsonObject = Record<string, unknown>

export function parseObject(raw: string): JsonObject {
  const value: unknown = JSON.parse(raw)
  return typeof value === 'object' && value !== null
    ? (value as JsonObject)
    : {}
}

export function text(value: unknown): string | null {
  if (typeof value === 'string' && value.length > 0) {
    return value
  }
  return typeof value === 'number' ? String(value) : null
}

export function field(value: unknown, key: string): unknown {
  return typeof value === 'object' && value !== null
    ? (value as JsonObject)[key]
    : undefined
}
