import { type RailId } from '@cashdeck/domain'

export const WEBHOOK_PROVIDERS = [
  'asaas',
  'inter',
  'mercado-pago',
  'pluggy',
  'notaas',
] as const
export type WebhookProvider = (typeof WEBHOOK_PROVIDERS)[number]

// Header names are lower case; the raw body is kept for signature checks.
export type WebhookDelivery = {
  provider: WebhookProvider
  headers: Readonly<Record<string, string>>
  query: Readonly<Record<string, string>>
  rawBody: string
}

// A webhook only names what changed. The work re-reads the provider API, so an
// authenticated body can trigger a refresh but never settle anything by itself.
export type WebhookSignal =
  | { kind: 'PAYMENT'; rail: RailId; reference: string }
  | { kind: 'OPEN_FINANCE_ITEM'; itemId: string }
  | { kind: 'INVOICE'; externalId: string }
  | { kind: 'IGNORED' }

export type WebhookEvent = { eventId: string; type: string } & WebhookSignal

export interface WebhookReader {
  readonly provider: WebhookProvider
  // Throws UnauthorizedError when the delivery is not from the provider.
  read(tenantId: string, delivery: WebhookDelivery): Promise<WebhookEvent[]>
}

export interface WebhookEventStore {
  // True the first time an event id is seen for the provider, false on a replay.
  remember(
    tenantId: string,
    provider: WebhookProvider,
    eventId: string,
    receivedAt: Date,
  ): Promise<boolean>
}
