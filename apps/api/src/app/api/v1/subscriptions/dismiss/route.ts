import { subscriptionDecisionSchema } from '@cashdeck/application'
import { route } from '@/server/api/handler'
import { ok, readJson } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const POST = route(
  'subscriptions:dismiss',
  async ({ request, tenantId, container }) => {
    const input = subscriptionDecisionSchema.parse(await readJson(request))
    return ok(
      await container.subscriptions.dismiss(tenantId, input.transactionId),
    )
  },
)
