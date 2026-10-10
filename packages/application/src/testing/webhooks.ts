import { UnauthorizedError } from '@/errors/errors'
import {
  type WebhookDelivery,
  type WebhookEvent,
  type WebhookEventStore,
  type WebhookProvider,
  type WebhookReader,
  type WebhookReceived,
  type WebhookSettlement,
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
// the events it was given.
export class FakeWebhookReader implements WebhookReader {
  constructor(
    readonly provider: WebhookProvider,
    private readonly events: WebhookEvent[] = [],
    private readonly token = 'test-token',
  ) {}

  async read(
    _tenantId: string,
    delivery: WebhookDelivery,
  ): Promise<WebhookEvent[]> {
    if (delivery.headers['x-test-token'] !== this.token) {
      throw new UnauthorizedError()
    }
    return this.events
  }
}
