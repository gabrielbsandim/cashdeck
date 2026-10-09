import { UnauthorizedError } from '@/errors/errors'
import {
  type WebhookDelivery,
  type WebhookEvent,
  type WebhookEventStore,
  type WebhookProvider,
  type WebhookReader,
} from '@/ports/webhooks'

export class InMemoryWebhookEventStore implements WebhookEventStore {
  private readonly seen = new Map<string, Date>()

  async remember(
    tenantId: string,
    provider: WebhookProvider,
    eventId: string,
    receivedAt: Date,
  ): Promise<boolean> {
    const id = `${tenantId}\u0000${provider}\u0000${eventId}`
    if (this.seen.has(id)) {
      return false
    }
    this.seen.set(id, receivedAt)
    return true
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
