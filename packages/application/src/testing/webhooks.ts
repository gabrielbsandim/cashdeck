import { UnauthorizedError } from '@/errors/errors'
import {
  type WebhookDelivery,
  type WebhookEvent,
  type WebhookEventStore,
  type WebhookProvider,
  type WebhookReader,
  type WebhookReceived,
  type WebhookSettlement,
  type WithdrawalCheck,
} from '@/ports/webhooks'

export type StoredWebhookEvent = WebhookReceived & {
  receivedAt: Date
} & (WebhookSettlement | Record<keyof WebhookSettlement, null>)

const keyOf = (tenantId: string, provider: string, eventId: string) =>
  `${tenantId}\u0000${provider}\u0000${eventId}`

export class InMemoryWebhookEventStore implements WebhookEventStore {
  private readonly seen = new Map<string, StoredWebhookEvent>()

  async remember(
    tenantId: string,
    provider: WebhookProvider,
    event: WebhookReceived,
    receivedAt: Date,
  ): Promise<boolean> {
    const id = keyOf(tenantId, provider, event.eventId)
    if (this.seen.has(id)) {
      return false
    }
    this.seen.set(id, {
      ...event,
      receivedAt,
      outcome: null,
      reason: null,
      processedAt: null,
    })
    return true
  }

  async reclaim(
    tenantId: string,
    provider: WebhookProvider,
    eventId: string,
    receivedAt: Date,
    staleBefore: Date,
  ): Promise<boolean> {
    const id = keyOf(tenantId, provider, eventId)
    const stored = this.seen.get(id)
    const abandoned =
      stored?.outcome === null && stored.receivedAt < staleBefore
    if (stored?.outcome !== 'FAILED' && !abandoned) {
      return false
    }
    this.seen.set(id, {
      ...(stored as StoredWebhookEvent),
      receivedAt,
      outcome: null,
      reason: null,
      processedAt: null,
    })
    return true
  }

  async settle(
    tenantId: string,
    provider: WebhookProvider,
    eventId: string,
    settlement: WebhookSettlement,
  ): Promise<void> {
    const id = keyOf(tenantId, provider, eventId)
    const stored = this.seen.get(id)
    if (!stored) {
      return
    }
    this.seen.set(id, { ...stored, ...settlement })
  }

  find(
    tenantId: string,
    provider: WebhookProvider,
    eventId: string,
  ): StoredWebhookEvent | null {
    return this.seen.get(keyOf(tenantId, provider, eventId)) ?? null
  }
}

// Accepts deliveries whose `x-test-token` header equals the token and returns
// the events, or the withdrawal check, it was given.
export class FakeWebhookReader implements WebhookReader {
  constructor(
    readonly provider: WebhookProvider,
    private readonly events: WebhookEvent[] = [],
    private readonly token = 'test-token',
    private readonly withdrawal: WithdrawalCheck = {
      rail: 'ASAAS',
      operation: 'TRANSFER',
      externalId: null,
      amountCents: null,
    },
  ) {}

  async read(
    _tenantId: string,
    delivery: WebhookDelivery,
  ): Promise<WebhookEvent[]> {
    this.authenticate(delivery)
    return this.events
  }

  async readWithdrawal(
    _tenantId: string,
    delivery: WebhookDelivery,
  ): Promise<WithdrawalCheck> {
    this.authenticate(delivery)
    return this.withdrawal
  }

  private authenticate(delivery: WebhookDelivery) {
    if (delivery.headers['x-test-token'] !== this.token) {
      throw new UnauthorizedError()
    }
  }
}
