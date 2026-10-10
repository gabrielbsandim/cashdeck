import { after } from 'next/server'
import {
  type WebhookDelivery,
  type WebhookProvider,
} from '@cashdeck/application'
import { handleError, ok } from '@/server/api/respond'
import { resolveTenant } from '@/server/api/tenant'
import { getContainer } from '@/server/container'
import { reportError } from '@/server/observability'

// Providers retry or pause a slow endpoint, so the work runs after the answer.
// `after` throws outside a request scope (tests, scripts): run it inline there.
export async function defer(
  task: () => Promise<unknown>,
  scope: string,
): Promise<void> {
  const guarded = () =>
    task().then(
      () => undefined,
      (error: unknown) => reportError(error, scope),
    )
  try {
    after(guarded)
  } catch {
    await guarded()
  }
}

async function deliveryOf(
  request: Request,
  provider: WebhookProvider,
): Promise<WebhookDelivery> {
  return {
    provider,
    headers: Object.fromEntries(request.headers),
    query: Object.fromEntries(new URL(request.url).searchParams),
    rawBody: await request.text(),
  }
}

// Webhooks skip the bearer token on purpose: each provider proves itself with
// its own signature or shared secret, checked by the reader before any work.
export function webhookRoute(provider: WebhookProvider) {
  const scope = `webhook:${provider}`
  return async (request: Request): Promise<Response> => {
    try {
      const container = getContainer()
      const tenantId = resolveTenant(request)
      const receipt = await container.receiveWebhook(
        tenantId,
        await deliveryOf(request, provider),
      )
      await defer(async () => {
        const outcomes = await container.processWebhookEvents(
          tenantId,
          provider,
          receipt.events,
        )
        for (const failed of outcomes.filter(o => o.outcome === 'FAILED')) {
          reportError(new Error(`${failed.eventId}: ${failed.reason}`), scope)
        }
      }, scope)
      return ok({
        received: receipt.events.length,
        duplicates: receipt.duplicates,
      })
    } catch (error) {
      return handleError(error, scope)
    }
  }
}
