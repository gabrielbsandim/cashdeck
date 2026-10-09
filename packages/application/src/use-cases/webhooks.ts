import { NotFoundError } from '@/errors/errors'
import { type WebhookDelivery, type WebhookEvent } from '@/ports/webhooks'
import { type Deps } from '@/use-cases/deps'
import { makeInvoiceLifecycle } from '@/use-cases/invoice-lifecycle'
import {
  makeOpenFinance,
  OPEN_FINANCE_PROVIDER,
} from '@/use-cases/open-finance'
import { makeReconcilePayments } from '@/use-cases/reconcile-payments'

export type WebhookReceipt = { events: WebhookEvent[]; duplicates: number }

// Authenticates the delivery and drops events already seen, so the route can
// answer at once and leave the work for later.
export function makeReceiveWebhook(
  deps: Pick<Deps, 'webhooks' | 'webhookEvents' | 'clock'>,
) {
  return async function receiveWebhook(
    tenantId: string,
    delivery: WebhookDelivery,
  ): Promise<WebhookReceipt> {
    const reader = deps.webhooks.get(delivery.provider)
    if (!reader) {
      throw new NotFoundError('Webhook provider')
    }
    const events = await reader.read(tenantId, delivery)
    const fresh: WebhookEvent[] = []
    for (const event of events) {
      const first = await deps.webhookEvents.remember(
        tenantId,
        delivery.provider,
        event.eventId,
        deps.clock.now(),
      )
      fresh.push(...(first ? [event] : []))
    }
    return { events: fresh, duplicates: events.length - fresh.length }
  }
}

export type WebhookOutcome = {
  eventId: string
  kind: WebhookEvent['kind']
  outcome: 'DONE' | 'IGNORED' | 'UNKNOWN' | 'FAILED'
  reason: string | null
}

type ProcessDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'institutions'
  | 'transactions'
  | 'connections'
  | 'openFinance'
  | 'bills'
  | 'payments'
  | 'railStatus'
  | 'idempotency'
  | 'settings'
  | 'invoices'
  | 'issuer'
  | 'audit'
  | 'clock'
  | 'ids'
>

type Handler = (
  tenantId: string,
  event: WebhookEvent,
) => Promise<Pick<WebhookOutcome, 'outcome' | 'reason'>>

const done = (found: boolean) => ({
  outcome: found ? ('DONE' as const) : ('UNKNOWN' as const),
  reason: null,
})

// The scheduled crons stay the backstop: an event lost here is picked up by the
// next reconcile, sync or invoice poll.
export function makeProcessWebhookEvents(deps: ProcessDeps) {
  const reconcile = makeReconcilePayments(deps)
  const openFinance = makeOpenFinance(deps)
  const lifecycle = makeInvoiceLifecycle(deps)

  const HANDLERS: Record<WebhookEvent['kind'], Handler> = {
    PAYMENT: async (tenantId, event) => {
      const { rail, reference } = event as Extract<
        WebhookEvent,
        { kind: 'PAYMENT' }
      >
      const result = await reconcile(tenantId, { rail, reference })
      const failure = result.failures[0]
      if (failure) {
        return { outcome: 'FAILED', reason: failure.reason }
      }
      return done(result.checked > 0)
    },
    OPEN_FINANCE_ITEM: async (tenantId, event) => {
      const { itemId } = event as Extract<
        WebhookEvent,
        { kind: 'OPEN_FINANCE_ITEM' }
      >
      const connection = await deps.connections.findByItemId(
        tenantId,
        OPEN_FINANCE_PROVIDER,
        itemId,
      )
      if (!connection) {
        return done(false)
      }
      await openFinance.sync(tenantId, connection.id)
      return done(true)
    },
    INVOICE: async (tenantId, event) => {
      const { externalId } = event as Extract<WebhookEvent, { kind: 'INVOICE' }>
      const invoice = await lifecycle.refreshExternal(tenantId, externalId)
      return done(invoice !== null)
    },
    IGNORED: async () => ({ outcome: 'IGNORED', reason: null }),
  }

  return async function processWebhookEvents(
    tenantId: string,
    events: readonly WebhookEvent[],
  ): Promise<WebhookOutcome[]> {
    const outcomes: WebhookOutcome[] = []
    for (const event of events) {
      const base = { eventId: event.eventId, kind: event.kind }
      try {
        outcomes.push({
          ...base,
          ...(await HANDLERS[event.kind](tenantId, event)),
        })
      } catch (error) {
        outcomes.push({ ...base, outcome: 'FAILED', reason: String(error) })
      }
    }
    return outcomes
  }
}
